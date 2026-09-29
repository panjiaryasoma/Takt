import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:takt_mobile/data/database/app_database.dart';
import 'package:takt_mobile/data/remote/plan_api_client.dart';
import 'package:takt_mobile/data/repositories/drift_evaluation_repository.dart';
import 'package:takt_mobile/data/repositories/drift_saved_plan_repository.dart';
import 'package:takt_mobile/data/repositories/drift_schedule_repository.dart';
import 'package:takt_mobile/data/repositories/saved_plan_repository.dart';
import 'package:takt_mobile/data/repositories/evaluation_repository.dart';
import 'package:takt_mobile/models/analysis_snapshot.dart';
import 'package:takt_mobile/models/decision_intent.dart';
import 'package:takt_mobile/models/enums.dart';
import 'package:takt_mobile/models/evaluation.dart';
import 'package:takt_mobile/models/plan_evaluation_wire.dart';
import 'package:takt_mobile/models/planning_input_draft.dart';
import 'package:takt_mobile/models/reevaluation_wire.dart';
import 'package:takt_mobile/screens/planning_setup_screen.dart';
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

  test('startPlanning replacement invalidates an in-flight prior lifecycle',
      () async {
    final api = _ControlledPlanApi(delayed: true);
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );
    final secondSnapshot = _snapshotFor(
      id: 'snapshot-b',
      competitionId: 'competition-b',
    );
    await _seedSnapshot(db, secondSnapshot);

    await host.startPlanning(snapshot);
    host.addTask(_task());
    final firstEvaluation = host.evaluate();
    await _waitFor(() => api.lastEvaluationRequest != null);

    await host.startPlanning(secondSnapshot);
    expect(host.phase, PlanningHostPhase.setup);
    expect(host.analysisSnapshot?.id, secondSnapshot.id);
    expect(host.draft, isNotNull);

    api.completeEvaluate();
    await firstEvaluation;

    expect(host.phase, PlanningHostPhase.setup);
    expect(host.analysisSnapshot?.id, secondSnapshot.id);
    expect(host.activeSession, isNull);
    expect(await evaluations.evaluationById(evaluationId), isNull);
    host.dispose();
  });

  testWidgets('Planning Setup freezes authoritative fields while request is active',
      (tester) async {
    final api = _ControlledPlanApi(delayed: true);
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );
    await host.startPlanning(snapshot);
    host.addTask(_task());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PlanningSetupScreen(host: host)),
      ),
    );

    await tester.tap(find.text('Evaluate'));
    await tester.pump();
    await _waitFor(() => api.lastEvaluationRequest != null);
    await tester.pump();

    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields, isNotEmpty);
    expect(fields.every((field) => field.enabled == false), isTrue);

    api.completeEvaluate();
    await tester.pumpAndSettle();
    host.dispose();
  });

  testWidgets('Planning Setup stays frozen while a result awaits Retry Save',
      (tester) async {
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

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PlanningSetupScreen(host: host)),
      ),
    );
    await tester.tap(find.text('Evaluate'));
    await tester.pumpAndSettle();

    expect(host.phase, PlanningHostPhase.persistenceError);
    expect(find.text('Retry local save'), findsOneWidget);
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields, isNotEmpty);
    expect(fields.every((field) => field.enabled == false), isTrue);
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

  test('UNCHANGED re-evaluation keeps accepted revision current', () async {
    final prior = await _persistAndAcceptPrior(
      evaluations,
      savedPlans,
      snapshot,
    );
    final api = _ReevaluationPlanApi(
      mode: _ReevaluationMode.unchanged,
      priorEvaluationId: prior.id,
      priorBasisFingerprint: prior.evaluationBasisFingerprint,
    );
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    await host.evaluate();

    expect(api.reevaluateCalls, 1);
    expect(host.phase, PlanningHostPhase.unchanged);
    expect(host.activeSession, isNull);
    expect(await evaluations.isStale(prior.id), isFalse);
    final plan = await savedPlans.planForCompetition(snapshot.competitionId);
    final detail = await savedPlans.loadDetail(plan!.id);
    expect(detail!.revisions, hasLength(1));
    expect(detail.summary.currentRevision.evaluationId, prior.id);
    host.dispose();
  });

  test('SUPERSEDED re-evaluation publishes fresh session and Accept creates revision 2',
      () async {
    final prior = await _persistAndAcceptPrior(
      evaluations,
      savedPlans,
      snapshot,
    );
    final api = _ReevaluationPlanApi(
      mode: _ReevaluationMode.superseded,
      priorEvaluationId: prior.id,
      priorBasisFingerprint: prior.evaluationBasisFingerprint,
    );
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    await host.evaluate();

    expect(host.phase, PlanningHostPhase.decision);
    expect(await evaluations.isStale(prior.id), isTrue);
    final session = host.activeSession!;
    expect(session.parsedResponse.evaluationId, _freshEvaluationId);

    await host.accept(
      session,
      AcceptCandidateIntent(
        sessionId: session.sessionId,
        evaluationId: session.parsedResponse.evaluationId,
        candidateId: primaryId,
        selectionSource: SelectionSource.primary,
      ),
    );

    expect(host.phase, PlanningHostPhase.accepted);
    final plan = await savedPlans.planForCompetition(snapshot.competitionId);
    final detail = await savedPlans.loadDetail(plan!.id);
    expect(detail!.revisions, hasLength(2));
    expect(detail.summary.currentRevision.revisionNumber, 2);
    expect(detail.summary.currentRevision.evaluationId, _freshEvaluationId);
    expect(detail.summary.stale, isFalse);
    host.dispose();
  });

  test('trusted SUPERSEDED failure marks prior stale and keeps old schedule active',
      () async {
    final prior = await _persistAndAcceptPrior(
      evaluations,
      savedPlans,
      snapshot,
    );
    final api = _ReevaluationPlanApi(
      mode: _ReevaluationMode.failure,
      priorEvaluationId: prior.id,
      priorBasisFingerprint: prior.evaluationBasisFingerprint,
    );
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    await host.evaluate();

    expect(host.phase, PlanningHostPhase.error);
    expect(host.failure?.code, 'PLANNING_EXECUTION_FAILED');
    expect(await evaluations.isStale(prior.id), isTrue);
    final active = await savedPlans.activeAcceptedBlocks();
    expect(active, hasLength(1));
    final plan = await savedPlans.planForCompetition(snapshot.competitionId);
    final detail = await savedPlans.loadDetail(plan!.id);
    expect(detail!.revisions, hasLength(1));
    expect(detail.summary.stale, isTrue);
    host.dispose();
  });

  test('unsupported re-evaluation contract requires explicit fresh baseline', () async {
    final prior = await _persistAndAcceptPrior(
      evaluations,
      savedPlans,
      snapshot,
    );
    final api = _ReevaluationPlanApi(
      mode: _ReevaluationMode.unsupported,
      priorEvaluationId: prior.id,
      priorBasisFingerprint: prior.evaluationBasisFingerprint,
    );
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    await host.evaluate();

    expect(host.phase, PlanningHostPhase.error);
    expect(host.canCreateFreshBaseline, isTrue);
    expect(api.evaluateCalls, 0);

    host.createFreshEvaluationBaseline();
    await host.evaluate();

    expect(api.evaluateCalls, 1);
    expect(host.phase, PlanningHostPhase.decision);
    expect(
      host.activeSession!.parsedResponse.evaluationId,
      _fallbackEvaluationId,
    );
    expect(await evaluations.isStale(prior.id), isFalse);
    host.dispose();
  });
}

enum _ReevaluationMode { unchanged, superseded, failure, unsupported }

const _freshEvaluationId = '22222222-2222-4222-8222-222222222222';
const _fallbackEvaluationId = '33333333-3333-4333-8333-333333333333';

final class _ReevaluationPlanApi implements PlanApiClient {
  _ReevaluationPlanApi({
    required this.mode,
    required this.priorEvaluationId,
    required this.priorBasisFingerprint,
  });

  final _ReevaluationMode mode;
  final String priorEvaluationId;
  final String priorBasisFingerprint;
  int evaluateCalls = 0;
  int reevaluateCalls = 0;

  @override
  Future<PlanEvaluateTransportResult> evaluate({
    required String evaluationRequestJson,
  }) async {
    evaluateCalls++;
    final raw = _decisionResponse(
      evaluationIdValue: _fallbackEvaluationId,
      basisFingerprint: List.filled(64, 'e').join(),
    );
    return PlanEvaluateTransportResult(
      evaluationRequestJson: evaluationRequestJson,
      evaluationResponseJson: raw,
      response: PlanEvaluateResponseV1.parse(raw),
    );
  }

  @override
  Future<PlanReevaluateTransportResult> reevaluate({
    required String priorEvaluationId,
    required String priorEvaluationResponseJson,
    required String currentEvaluationRequestJson,
  }) async {
    reevaluateCalls++;
    expect(priorEvaluationId, this.priorEvaluationId);
    expect(
      PlanEvaluateResponseV1.parse(priorEvaluationResponseJson).basis.fingerprint,
      priorBasisFingerprint,
    );

    if (mode == _ReevaluationMode.unsupported) {
      throw const PlanApiFailure(
        code: 'UNSUPPORTED_REEVALUATION_CONTRACT',
        stage: 'reevaluation',
        message: 'Prior evaluation basis structural version is not supported.',
        retryable: false,
      );
    }

    if (mode == _ReevaluationMode.failure) {
      final transition = ReevaluationTransitionWire.fromValue({
        'kind': 'SUPERSEDED',
        'prior_evaluation_id': this.priorEvaluationId,
        'prior_basis_fingerprint': priorBasisFingerprint,
        'current_basis_fingerprint': List.filled(64, 'c').join(),
        'prior_evaluation_freshness': 'STALE',
        'change_reasons': ['PLANNING_BASIS_CHANGED'],
      });
      final errorJson = jsonEncode({
        'code': 'PLANNING_EXECUTION_FAILED',
        'message': 'The planning pipeline could not complete execution.',
        'stage': 'planning',
        'details': <Object?>[],
      });
      throw PlanApiFailure(
        code: 'PLANNING_EXECUTION_FAILED',
        stage: 'planning',
        message: 'The planning pipeline could not complete execution.',
        retryable: true,
        statusCode: 500,
        transportRequestJson: _transportRequest(currentEvaluationRequestJson),
        transportResponseJson: jsonEncode({
          'error': jsonDecode(errorJson),
          'transition': transition.toJson(),
        }),
        transition: transition,
        errorJson: errorJson,
      );
    }

    if (mode == _ReevaluationMode.unchanged) {
      final transition = ReevaluationTransitionWire.fromValue({
        'kind': 'UNCHANGED',
        'prior_evaluation_id': this.priorEvaluationId,
        'prior_basis_fingerprint': priorBasisFingerprint,
        'current_basis_fingerprint': priorBasisFingerprint,
        'prior_evaluation_freshness': 'CURRENT',
        'change_reasons': <String>[],
      });
      final raw = jsonEncode({
        'transition': transition.toJson(),
        'evaluation': null,
      });
      return PlanReevaluateTransportResult(
        transportRequestJson: _transportRequest(currentEvaluationRequestJson),
        transportResponseJson: raw,
        evaluationRequestJson: currentEvaluationRequestJson,
        success: PlanReevaluateSuccessWire.parse(raw),
      );
    }

    final freshFingerprint = List.filled(64, 'd').join();
    final freshRaw = _decisionResponse(
      evaluationIdValue: _freshEvaluationId,
      basisFingerprint: freshFingerprint,
    );
    final transition = ReevaluationTransitionWire.fromValue({
      'kind': 'SUPERSEDED',
      'prior_evaluation_id': this.priorEvaluationId,
      'prior_basis_fingerprint': priorBasisFingerprint,
      'current_basis_fingerprint': freshFingerprint,
      'prior_evaluation_freshness': 'STALE',
      'change_reasons': ['PLANNING_BASIS_CHANGED'],
    });
    final raw = jsonEncode({
      'transition': transition.toJson(),
      'evaluation': jsonDecode(freshRaw),
    });
    return PlanReevaluateTransportResult(
      transportRequestJson: _transportRequest(currentEvaluationRequestJson),
      transportResponseJson: raw,
      evaluationRequestJson: currentEvaluationRequestJson,
      success: PlanReevaluateSuccessWire.parse(raw),
    );
  }

  String _transportRequest(String currentRequest) => jsonEncode({
        'prior': {
          'evaluation_id': priorEvaluationId,
          'basis_fingerprint': priorBasisFingerprint,
        },
        'current': jsonDecode(currentRequest),
      });

  @override
  void close() {}
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

Future<Evaluation> _persistAndAcceptPrior(
  DriftEvaluationRepository evaluations,
  DriftSavedPlanRepository savedPlans,
  AnalysisSnapshot snapshot,
) async {
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
  return prior;
}

String _decisionResponse({
  required String evaluationIdValue,
  required String basisFingerprint,
}) {
  final raw = jsonEncode(decisionFixture())
      .replaceAll(evaluationId, evaluationIdValue)
      .replaceAll(List.filled(64, 'b').join(), basisFingerprint);
  return raw;
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

AnalysisSnapshot _snapshot() => _snapshotFor(
      id: 'snapshot-2',
      competitionId: 'competition-1',
    );

AnalysisSnapshot _snapshotFor({
  required String id,
  required String competitionId,
}) {
  final hash = List.filled(64, 'a').join();
  return AnalysisSnapshot(
    id: id,
    competitionId: competitionId,
    reportVersion: 2,
    assemblyMaterialFingerprint: hash,
    sourceSetFingerprint: null,
    wireFingerprint: List.filled(64, 'f').join(),
    reportChanged: true,
    responseJson: jsonEncode({
      'report_bundle': {
        'report': {
          'competition_id': competitionId,
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
