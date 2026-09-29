import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:takt_mobile/data/database/app_database.dart';
import 'package:takt_mobile/data/remote/plan_api_client.dart';
import 'package:takt_mobile/data/repositories/drift_evaluation_repository.dart';
import 'package:takt_mobile/data/repositories/drift_saved_plan_repository.dart';
import 'package:takt_mobile/data/repositories/drift_schedule_repository.dart';
import 'package:takt_mobile/data/repositories/evaluation_repository.dart';
import 'package:takt_mobile/models/analysis_snapshot.dart';
import 'package:takt_mobile/models/enums.dart';
import 'package:takt_mobile/models/evaluation.dart';
import 'package:takt_mobile/models/plan_evaluation_wire.dart';
import 'package:takt_mobile/models/planning_input_draft.dart';
import 'package:takt_mobile/models/reevaluation_wire.dart';
import 'package:takt_mobile/viewmodels/planning_host_view_model.dart';

import 'support/decision_fixture.dart';

void main() {
  late AppDatabase db;
  late DriftEvaluationRepository evaluations;
  late DriftSavedPlanRepository savedPlans;
  late DriftScheduleRepository schedule;
  late AnalysisSnapshot snapshot;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    evaluations = DriftEvaluationRepository(db);
    savedPlans = DriftSavedPlanRepository(db);
    schedule = DriftScheduleRepository(db);
    await db.initialize();
    await schedule.initialize();
    snapshot = _snapshot();
    await _seedSnapshot(db, snapshot);
  });

  tearDown(() => db.close());

  test('persisted evaluation is reloaded before publishing session', () async {
    final api = _ControlledPlanApi();
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    host.addTask(_task());
    await host.evaluate();

    expect(api.evaluateCalls, 1);
    expect(host.phase, PlanningHostPhase.decision);
    expect(host.activeSession, isNotNull);
    final id = host.activeSession!.parsedResponse.evaluationId;
    final persisted = await evaluations.evaluationById(id);
    expect(persisted, isNotNull);
    expect(host.activeSession!.evaluationRequestJson, persisted!.requestJson);
    expect(host.activeSession!.evaluationResponseJson, persisted.responseJson);
    host.dispose();
  });

  test('late HTTP response is dropped after input revision changes', () async {
    final api = _ControlledPlanApi(delayed: true);
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    host.addTask(_task());
    final future = host.evaluate();
    await _waitFor(() => api.lastEvaluationRequest != null);

    host.replaceReadiness(
      const ReadinessContextDraft(age: 21),
    );
    api.completeEvaluate();
    await future;

    expect(host.activeSession, isNull);
    expect(
      await evaluations.evaluationById(evaluationId),
      isNull,
    );
    host.dispose();
  });

  test('Retry Save persists without issuing a second HTTP request', () async {
    final api = _ControlledPlanApi();
    final failOnce = _FailOnceEvaluationRepository(evaluations);
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: failOnce,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    host.addTask(_task());
    await host.evaluate();

    expect(host.phase, PlanningHostPhase.persistenceError);
    expect(host.activeSession, isNull);
    expect(api.evaluateCalls, 1);

    await host.retryPersistence();

    expect(api.evaluateCalls, 1);
    expect(host.phase, PlanningHostPhase.decision);
    expect(host.activeSession, isNotNull);
    expect(
      await evaluations.evaluationById(evaluationId),
      isNotNull,
    );
    host.dispose();
  });

  test('re-evaluate draft seeds semantic values from prior evaluation', () async {
    final prior = await evaluations.persistEvaluation(
      analysisSnapshot: snapshot,
      evaluationRequestJson: _priorRequest(),
      evaluationResponseJson: jsonEncode(decisionFixture()),
      planningWindowPolicyJson: jsonEncode({
        'policy_version': 'planning-window-policy-v1',
        'timezone': 'Asia/Jakarta',
        'start_local': '09:00',
        'end_local': '20:00',
      }),
    );
    await savedPlans.acceptEvaluation(
      evaluationId: prior.id,
      candidateId: primaryId,
      selectionSource: SelectionSource.primary,
    );

    // Global defaults deliberately diverge from the accepted evaluation.
    await schedule.savePlanningPreferences(
      (await schedule.loadState()).preferences.copyWith(
        maxProjectMinutesPerDay: 30,
        preferredFocusMinutes: 15,
        bufferTargetMinutes: 0,
        updatedAtEpochMs: 2,
      ),
    );

    final host = PlanningHostViewModel(
      apiClient: _ControlledPlanApi(),
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );
    await host.startPlanning(snapshot);

    final draft = host.draft!;
    expect(host.hasAcceptedPlan, isTrue);
    expect(draft.readinessContext.age, 21);
    expect(draft.readinessContext.studentStatus, isTrue);
    expect(draft.readinessContext.country, 'ID');
    expect(draft.preferences.maxProjectMinutesPerDay, 300);
    expect(draft.preferences.preferredFocusMinutes, 100);
    expect(draft.preferences.bufferTargetMinutes, 45);
    expect(draft.windowPolicy.startLocal, '09:00');
    expect(draft.windowPolicy.endLocal, '20:00');
    expect(draft.tasks.single.taskId, 'task-draft');
    host.dispose();
  });
}

final class _ControlledPlanApi implements PlanApiClient {
  _ControlledPlanApi({this.delayed = false});

  final bool delayed;
  int evaluateCalls = 0;
  String? lastEvaluationRequest;
  Completer<PlanEvaluateTransportResult>? _pending;

  @override
  Future<PlanEvaluateTransportResult> evaluate({
    required String evaluationRequestJson,
  }) {
    evaluateCalls++;
    lastEvaluationRequest = evaluationRequestJson;
    if (delayed) {
      _pending = Completer<PlanEvaluateTransportResult>();
      return _pending!.future;
    }
    return Future.value(_result(evaluationRequestJson));
  }

  void completeEvaluate() {
    final request = lastEvaluationRequest;
    if (request == null || _pending == null) {
      throw StateError('No pending evaluate request.');
    }
    _pending!.complete(_result(request));
  }

  PlanEvaluateTransportResult _result(String request) {
    final raw = jsonEncode(decisionFixture());
    return PlanEvaluateTransportResult(
      evaluationRequestJson: request,
      evaluationResponseJson: raw,
      response: PlanEvaluateResponseV1.parse(raw),
    );
  }

  @override
  Future<PlanReevaluateTransportResult> reevaluate({
    required String priorEvaluationId,
    required String priorEvaluationResponseJson,
    required String currentEvaluationRequestJson,
  }) {
    throw UnimplementedError();
  }

  @override
  void close() {}
}

final class _FailOnceEvaluationRepository implements EvaluationRepository {
  _FailOnceEvaluationRepository(this.delegate);

  final EvaluationRepository delegate;
  bool failed = false;

  @override
  Future<void> initialize() => delegate.initialize();

  @override
  Future<Evaluation?> evaluationById(String evaluationId) =>
      delegate.evaluationById(evaluationId);

  @override
  Future<Evaluation> persistEvaluation({
    required AnalysisSnapshot analysisSnapshot,
    required String evaluationRequestJson,
    required String evaluationResponseJson,
    required String planningWindowPolicyJson,
  }) {
    if (!failed) {
      failed = true;
      throw StateError('simulated local write failure');
    }
    return delegate.persistEvaluation(
      analysisSnapshot: analysisSnapshot,
      evaluationRequestJson: evaluationRequestJson,
      evaluationResponseJson: evaluationResponseJson,
      planningWindowPolicyJson: planningWindowPolicyJson,
    );
  }

  @override
  Future<ReevaluationPersistenceResult> persistReevaluation({
    required String priorEvaluationId,
    required ReevaluationTransitionWire transition,
    required String transportRequestJson,
    required String transportResponseJson,
    required String? errorJson,
    AnalysisSnapshot? currentAnalysisSnapshot,
    String? currentEvaluationRequestJson,
    String? currentEvaluationResponseJson,
    String? planningWindowPolicyJson,
  }) =>
      delegate.persistReevaluation(
        priorEvaluationId: priorEvaluationId,
        transition: transition,
        transportRequestJson: transportRequestJson,
        transportResponseJson: transportResponseJson,
        errorJson: errorJson,
        currentAnalysisSnapshot: currentAnalysisSnapshot,
        currentEvaluationRequestJson: currentEvaluationRequestJson,
        currentEvaluationResponseJson: currentEvaluationResponseJson,
        planningWindowPolicyJson: planningWindowPolicyJson,
      );

  @override
  Future<bool> isStale(String evaluationId) => delegate.isStale(evaluationId);

  @override
  Future<void> close() => delegate.close();
}

Future<void> _waitFor(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition was not reached.');
}

PlanningTaskDraft _task() => PlanningTaskDraft(
      taskId: 'task-draft',
      name: 'Build prototype',
      mandatory: true,
      dependencies: const [],
      effortMinMinutes: 30,
      effortLikelyMinutes: 30,
      effortMaxMinutes: 30,
      assumptions: const ['Confirmed effort.'],
    );

AnalysisSnapshot _snapshot() {
  final hash = List.filled(64, 'a').join();
  return AnalysisSnapshot(
    id: 'snapshot-2',
    competitionId: 'competition-1',
    reportVersion: 2,
    assemblyMaterialFingerprint: hash,
    sourceSetFingerprint: null,
    wireFingerprint: List.filled(64, 'f').join(),
    reportChanged: true,
    responseJson: jsonEncode({
      'report_bundle': {
        'report': {
          'competition_id': 'competition-1',
          'report_version': 2,
          'canonical_fields': {
            'submission_deadline': {
              'state': 'VERIFIED',
              'value': '2026-10-10T16:00:00Z',
              'normalized_value': '2026-10-10T16:00:00Z',
            },
          },
        },
        'ref': {
          'assembly_material_fingerprint': hash,
        },
      },
    }),
    cachedAtEpochMs: 1,
  );
}

Future<void> _seedSnapshot(
  AppDatabase db,
  AnalysisSnapshot snapshot,
) async {
  await db.customStatement(
    '''
INSERT INTO competitions (
  id, created_at_epoch_ms, updated_at_epoch_ms
) VALUES (?, ?, ?)
''',
    [snapshot.competitionId, 1, 1],
  );
  await db.customStatement(
    '''
INSERT INTO analysis_snapshots (
  id, competition_id, report_version, assembly_material_fingerprint,
  source_set_fingerprint, wire_fingerprint, report_changed,
  response_json, cached_at_epoch_ms
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
    [
      snapshot.id,
      snapshot.competitionId,
      snapshot.reportVersion,
      snapshot.assemblyMaterialFingerprint,
      null,
      snapshot.wireFingerprint,
      1,
      snapshot.responseJson,
      snapshot.cachedAtEpochMs,
    ],
  );
}

String _priorRequest() => jsonEncode({
      'report_bundle': {
        'report': {
          'competition_id': 'competition-1',
          'report_version': 2,
          'canonical_fields': {
            'competition_name': {
              'state': 'VERIFIED',
              'value': 'Demo Hackathon',
              'normalized_value': 'Demo Hackathon',
            },
            'submission_deadline': {
              'state': 'VERIFIED',
              'value': '2026-10-10T16:00:00Z',
              'normalized_value': '2026-10-10T16:00:00Z',
            },
          },
        },
        'ref': {
          'assembly_material_fingerprint': List.filled(64, 'a').join(),
        },
      },
      'readiness_context': {
        'user': {
          'age': 21,
          'student_status': true,
          'country': 'ID',
        },
        'selected_scope': 'student',
        'require_technology_information': false,
      },
      'planning': {
        'workload': {
          'tasks': [_task().toWire()],
          'assumptions': <Object?>[],
        },
        'availability': {
          'preferences': {
            'timezone': 'Asia/Jakarta',
            'max_project_minutes_per_day': 300,
            'preferred_focus_minutes': 100,
            'buffer_target_minutes': 45,
          },
        },
      },
    });
