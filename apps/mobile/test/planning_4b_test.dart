import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takt_mobile/data/database/app_database.dart';
import 'package:takt_mobile/data/repositories/drift_evaluation_repository.dart';
import 'package:takt_mobile/data/repositories/drift_saved_plan_repository.dart';
import 'package:takt_mobile/data/repositories/schedule_repository.dart';
import 'package:takt_mobile/models/analysis_snapshot.dart';
import 'package:takt_mobile/models/enums.dart';
import 'package:takt_mobile/models/planning_input_draft.dart';
import 'package:takt_mobile/models/planning_preferences.dart';
import 'package:takt_mobile/models/reevaluation_wire.dart';
import 'package:takt_mobile/services/planning_request_assembler.dart';

import 'support/decision_fixture.dart';

void main() {
  group('planning window policy', () {
    test('expands visible Asia/Jakarta policy into concrete aware windows', () {
      final assembler = PlanningRequestAssembler(
        now: () => DateTime.utc(2026, 9, 30, 0),
      );
      final prefs = _preferences('Asia/Jakarta');
      final result = assembler.assemble(
        analysisSnapshot: _analysisSnapshot(
          deadline: '2026-10-02T16:00:00Z',
        ),
        draft: PlanningDraft(
          readinessContext: const ReadinessContextDraft(),
          tasks: [_task()],
          preferences: prefs,
          windowPolicy: PlanningWindowPolicyV1.defaults('Asia/Jakarta'),
        ),
        schedule: _schedule(prefs),
        acceptedBlocks: const [],
      );

      final request = jsonDecode(result.requestJson) as Map<String, dynamic>;
      final planning = request['planning'] as Map<String, dynamic>;
      final availability = planning['availability'] as Map<String, dynamic>;
      final windows = availability['work_windows'] as List<dynamic>;

      expect(windows, hasLength(3));
      expect(
        (windows.first as Map<String, dynamic>)['start'],
        '2026-09-30T08:00:00+07:00',
      );
      expect(
        (windows.first as Map<String, dynamic>)['end'],
        '2026-09-30T22:00:00+07:00',
      );
      expect(
        jsonDecode(result.windowPolicyJson),
        {
          'end_local': '22:00',
          'policy_version': 'planning-window-policy-v1',
          'start_local': '08:00',
          'timezone': 'Asia/Jakarta',
        },
      );
    });

    test('rejects a work-window boundary in a DST gap', () {
      final assembler = PlanningRequestAssembler(
        now: () => DateTime.utc(2026, 3, 8, 5, 30),
      );
      final prefs = _preferences('America/New_York');

      expect(
        () => assembler.assemble(
          analysisSnapshot: _analysisSnapshot(
            deadline: '2026-03-09T04:00:00Z',
          ),
          draft: PlanningDraft(
            readinessContext: const ReadinessContextDraft(),
            tasks: [_task()],
            preferences: prefs,
            windowPolicy: PlanningWindowPolicyV1(
              timezone: 'America/New_York',
              startMinutesOfDay: 2 * 60 + 30,
              endMinutesOfDay: 4 * 60,
            ),
          ),
          schedule: _schedule(prefs),
          acceptedBlocks: const [],
        ),
        throwsA(
          isA<PlanningInputException>().having(
            (error) => error.code,
            'code',
            'PLANNING_INPUT_UNAVAILABLE',
          ),
        ),
      );
    });

    test('rejects a work-window boundary in a DST fold', () {
      final assembler = PlanningRequestAssembler(
        now: () => DateTime.utc(2026, 11, 1, 4, 30),
      );
      final prefs = _preferences('America/New_York');

      expect(
        () => assembler.assemble(
          analysisSnapshot: _analysisSnapshot(
            deadline: '2026-11-02T05:00:00Z',
          ),
          draft: PlanningDraft(
            readinessContext: const ReadinessContextDraft(),
            tasks: [_task()],
            preferences: prefs,
            windowPolicy: PlanningWindowPolicyV1(
              timezone: 'America/New_York',
              startMinutesOfDay: 1 * 60 + 30,
              endMinutesOfDay: 3 * 60,
            ),
          ),
          schedule: _schedule(prefs),
          acceptedBlocks: const [],
        ),
        throwsA(isA<PlanningInputException>()),
      );
    });
  });

  group('4B persistence', () {
    late AppDatabase db;
    late DriftEvaluationRepository evaluations;
    late DriftSavedPlanRepository savedPlans;
    late AnalysisSnapshot snapshot;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      evaluations = DriftEvaluationRepository(
        db,
        now: () => DateTime.utc(2026, 9, 30, 8),
      );
      savedPlans = DriftSavedPlanRepository(
        db,
        now: () => DateTime.utc(2026, 9, 30, 8, 5),
      );
      await db.initialize();
      snapshot = _analysisSnapshot();
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
    });

    tearDown(() => db.close());

    test('Accept snapshots persisted evaluation and is idempotent', () async {
      final evaluation = await evaluations.persistEvaluation(
        analysisSnapshot: snapshot,
        evaluationRequestJson: _evaluationRequest(),
        evaluationResponseJson: jsonEncode(decisionFixture()),
        planningWindowPolicyJson: _windowPolicyJson(),
      );

      final first = await savedPlans.acceptEvaluation(
        evaluationId: evaluation.id,
        candidateId: primaryId,
        selectionSource: SelectionSource.primary,
      );
      final second = await savedPlans.acceptEvaluation(
        evaluationId: evaluation.id,
        candidateId: primaryId,
        selectionSource: SelectionSource.primary,
      );

      expect(second.id, first.id);
      final plan = await savedPlans.planForCompetition(snapshot.competitionId);
      expect(plan, isNotNull);
      final detail = await savedPlans.loadDetail(plan!.id);
      expect(detail, isNotNull);
      expect(detail!.revisions, hasLength(1));
      expect(detail.tasks, hasLength(1));
      expect(detail.tasks.single.task.domainTaskId, 'task-draft');
      expect(detail.tasks.single.progress.progressPercent, 0);
      expect(detail.tasks.single.progress.actualMinutes, isNull);
      expect(detail.acceptedCommitments, hasLength(1));
      expect(
        detail.acceptedCommitments.single.allocatedMinutes,
        30,
      );
      expect(await savedPlans.activeAcceptedBlocks(), hasLength(1));

      await expectLater(
        savedPlans.acceptEvaluation(
          evaluationId: evaluation.id,
          candidateId: alternativeId,
          selectionSource: SelectionSource.alternative,
        ),
        throwsA(isA<SavedPlanIntegrityException>()),
      );
    });

    test('accepted persistence leaves no foreign-key violations', () async {
      final evaluation = await evaluations.persistEvaluation(
        analysisSnapshot: snapshot,
        evaluationRequestJson: _evaluationRequest(),
        evaluationResponseJson: jsonEncode(decisionFixture()),
        planningWindowPolicyJson: _windowPolicyJson(),
      );

      await savedPlans.acceptEvaluation(
        evaluationId: evaluation.id,
        candidateId: primaryId,
        selectionSource: SelectionSource.primary,
      );

      final violations =
          await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violations, isEmpty);
    });

    test('Accept transaction rolls back every child when block insert fails',
        () async {
      final evaluation = await evaluations.persistEvaluation(
        analysisSnapshot: snapshot,
        evaluationRequestJson: _evaluationRequest(),
        evaluationResponseJson: jsonEncode(decisionFixture()),
        planningWindowPolicyJson: _windowPolicyJson(),
      );
      await db.customStatement(
        '''
CREATE TRIGGER fail_6b_accepted_commitment
BEFORE INSERT ON accepted_commitments
BEGIN
  SELECT RAISE(ABORT, 'simulated 6B accepted block failure');
END
''',
      );

      await expectLater(
        savedPlans.acceptEvaluation(
          evaluationId: evaluation.id,
          candidateId: primaryId,
          selectionSource: SelectionSource.primary,
        ),
        throwsA(anything),
      );

      for (final table in [
        'saved_plans',
        'saved_plan_revisions',
        'saved_plan_tasks',
        'task_progress',
        'accepted_commitments',
      ]) {
        final row =
            await db.customSelect('SELECT COUNT(*) AS count FROM $table').getSingle();
        expect(row.data['count'], 0, reason: '$table must roll back atomically');
      }
      final violations =
          await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violations, isEmpty);
    });

    test('5A acceptance lineage consumes the shared backend/mobile golden',
        () async {
      final goldenResponseJson =
          File('../../tests/fixtures/api/plan_evaluate_response_v1.json')
              .readAsStringSync();
      final response =
          jsonDecode(goldenResponseJson) as Map<String, dynamic>;
      final planning = response['planning'] as Map<String, dynamic>;
      final candidates = planning['candidates'] as List<dynamic>;
      final primary = candidates
          .cast<Map<String, dynamic>>()
          .singleWhere(
            (candidate) =>
                (candidate['ref'] as Map<String, dynamic>)['candidate_id'] ==
                'candidate-001',
          );
      final sourceBlock =
          (primary['work_blocks'] as List<dynamic>).single
              as Map<String, dynamic>;

      final reportHash = List.filled(64, 'b').join();
      final goldenSnapshot = AnalysisSnapshot(
        id: 'snapshot-shared-golden',
        competitionId: 'cmp-ready',
        reportVersion: 4,
        assemblyMaterialFingerprint: reportHash,
        sourceSetFingerprint: null,
        wireFingerprint: List.filled(64, 'e').join(),
        reportChanged: true,
        responseJson: jsonEncode({
          'report_bundle': {
            'report': {
              'competition_id': 'cmp-ready',
              'report_version': 4,
            },
            'ref': {
              'assembly_material_fingerprint': reportHash,
            },
          },
        }),
        cachedAtEpochMs: 2,
      );
      await db.customStatement(
        '''
INSERT INTO competitions (
  id, created_at_epoch_ms, updated_at_epoch_ms
) VALUES (?, ?, ?)
''',
        [goldenSnapshot.competitionId, 2, 2],
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
          goldenSnapshot.id,
          goldenSnapshot.competitionId,
          goldenSnapshot.reportVersion,
          goldenSnapshot.assemblyMaterialFingerprint,
          null,
          goldenSnapshot.wireFingerprint,
          1,
          goldenSnapshot.responseJson,
          goldenSnapshot.cachedAtEpochMs,
        ],
      );

      final goldenRequestJson = jsonEncode({
        'report_bundle': {
          'report': {
            'competition_id': 'cmp-ready',
            'report_version': 4,
            'canonical_fields': {
              'competition_name': {
                'state': 'VERIFIED',
                'value': 'Demo Hackathon',
                'normalized_value': 'Demo Hackathon',
              },
              'submission_deadline': {
                'state': 'VERIFIED',
                'value': '2026-09-30T23:45:00Z',
                'normalized_value': '2026-09-30T23:45:00Z',
              },
            },
          },
          'ref': {
            'assembly_material_fingerprint': reportHash,
          },
        },
        'planning': {
          'workload': {
            'tasks': [
              {
                'task_id': 'task-1',
                'name': 'Build demo',
                'mandatory': true,
                'dependencies': <String>[],
                'effort_min_minutes': 60,
                'effort_likely_minutes': 60,
                'effort_max_minutes': 60,
                'assumptions': ['single-person estimate'],
              },
            ],
          },
          'availability': {
            'preferences': {
              'timezone': 'UTC',
            },
          },
        },
      });
      final goldenWindowPolicy = jsonEncode({
        'policy_version': 'planning-window-policy-v1',
        'timezone': 'UTC',
        'start_local': '08:00',
        'end_local': '22:00',
      });

      final evaluation = await evaluations.persistEvaluation(
        analysisSnapshot: goldenSnapshot,
        evaluationRequestJson: goldenRequestJson,
        evaluationResponseJson: goldenResponseJson,
        planningWindowPolicyJson: goldenWindowPolicy,
      );
      final revision = await savedPlans.acceptEvaluation(
        evaluationId: evaluation.id,
        candidateId: 'candidate-001',
        selectionSource: SelectionSource.primary,
      );
      final detail = await savedPlans.loadDetail(revision.savedPlanId);

      expect(detail, isNotNull);
      expect(revision.evaluationId, evaluation.id);
      expect(detail!.summary.currentRevision.evaluationId, evaluation.id);

      final persistedTask = detail.tasks.singleWhere(
        (state) => state.task.domainTaskId == sourceBlock['task_id'],
      );
      final accepted = detail.acceptedCommitments.single;
      expect(accepted.savedPlanRevisionId, revision.id);
      expect(accepted.savedPlanTaskId, persistedTask.task.id);

      final persistedSourceBlock =
          jsonDecode(accepted.sourceBlockJson) as Map<String, dynamic>;
      expect(persistedSourceBlock, sourceBlock);
      expect(
        accepted.originalAvailabilitySource,
        sourceBlock['availability_source'],
      );
    });

    test('fresh accepted evaluation creates a linear revision and resets progress',
        () async {
      final firstEvaluation = await evaluations.persistEvaluation(
        analysisSnapshot: snapshot,
        evaluationRequestJson: _evaluationRequest(),
        evaluationResponseJson: jsonEncode(decisionFixture()),
        planningWindowPolicyJson: _windowPolicyJson(),
      );
      final firstRevision = await savedPlans.acceptEvaluation(
        evaluationId: firstEvaluation.id,
        candidateId: primaryId,
        selectionSource: SelectionSource.primary,
      );
      final firstDetail = await savedPlans.loadDetail(firstRevision.savedPlanId);
      await savedPlans.updateTaskProgress(
        savedPlanTaskId: firstDetail!.tasks.single.task.id,
        progressPercent: 80,
        actualMinutes: 75,
      );

      const secondEvaluationId =
          '22222222-2222-4222-8222-222222222222';
      final secondResponse = jsonEncode(decisionFixture())
          .replaceAll(evaluationId, secondEvaluationId);
      final secondEvaluation = await evaluations.persistEvaluation(
        analysisSnapshot: snapshot,
        evaluationRequestJson: _evaluationRequest(),
        evaluationResponseJson: secondResponse,
        planningWindowPolicyJson: _windowPolicyJson(),
      );
      final secondRevision = await savedPlans.acceptEvaluation(
        evaluationId: secondEvaluation.id,
        candidateId: primaryId,
        selectionSource: SelectionSource.primary,
      );

      expect(secondRevision.revisionNumber, 2);
      expect(secondRevision.supersedesRevisionId, firstRevision.id);
      final detail = await savedPlans.loadDetail(firstRevision.savedPlanId);
      expect(detail!.revisions, hasLength(2));
      expect(detail.tasks.single.progress.progressPercent, 0);
      expect(detail.tasks.single.progress.actualMinutes, isNull);
      final active = await savedPlans.activeAcceptedBlocks();
      expect(active, hasLength(1));
      expect(active.single.savedPlanRevisionId, secondRevision.id);
    });

    test('trusted SUPERSEDED failure marks stale but keeps accepted schedule active',
        () async {
      final evaluation = await evaluations.persistEvaluation(
        analysisSnapshot: snapshot,
        evaluationRequestJson: _evaluationRequest(),
        evaluationResponseJson: jsonEncode(decisionFixture()),
        planningWindowPolicyJson: _windowPolicyJson(),
      );
      final revision = await savedPlans.acceptEvaluation(
        evaluationId: evaluation.id,
        candidateId: primaryId,
        selectionSource: SelectionSource.primary,
      );

      final transition = ReevaluationTransitionWire.fromValue({
        'kind': 'SUPERSEDED',
        'prior_evaluation_id': evaluation.id,
        'prior_basis_fingerprint': evaluation.evaluationBasisFingerprint,
        'current_basis_fingerprint': List.filled(64, 'c').join(),
        'prior_evaluation_freshness': 'STALE',
        'change_reasons': ['PLANNING_BASIS_CHANGED'],
      });
      await evaluations.persistReevaluation(
        priorEvaluationId: evaluation.id,
        transition: transition,
        transportRequestJson: '{"prior":"transport"}',
        transportResponseJson: '{"error":{"code":"INTERNAL_ERROR"}}',
        errorJson: '{"code":"INTERNAL_ERROR"}',
      );
      await savedPlans.refresh();

      final detail = await savedPlans.loadDetail(revision.savedPlanId);
      expect(detail!.summary.stale, isTrue);
      final active = await savedPlans.activeAcceptedBlocks();
      expect(active, hasLength(1));
      expect(active.single.savedPlanRevisionId, revision.id);
    });

    test('Accept stays successful when post-commit summary refresh cannot render',
        () async {
      final request = jsonDecode(_evaluationRequest()) as Map<String, dynamic>;
      final bundle = request['report_bundle'] as Map<String, dynamic>;
      final report = bundle['report'] as Map<String, dynamic>;
      final fields = report['canonical_fields'] as Map<String, dynamic>;
      fields.remove('submission_deadline');

      final evaluation = await evaluations.persistEvaluation(
        analysisSnapshot: snapshot,
        evaluationRequestJson: jsonEncode(request),
        evaluationResponseJson: jsonEncode(decisionFixture()),
        planningWindowPolicyJson: _windowPolicyJson(),
      );

      final revision = await savedPlans.acceptEvaluation(
        evaluationId: evaluation.id,
        candidateId: primaryId,
        selectionSource: SelectionSource.primary,
      );

      expect(revision.evaluationId, evaluation.id);
      final rows = await db.customSelect(
        'SELECT id FROM saved_plan_revisions WHERE evaluation_id = ?',
        variables: [Variable<String>(evaluation.id)],
      ).get();
      expect(rows, hasLength(1));
    });

    test('accepted plan, task progress, and blocks survive database restart',
        () async {
      final dir =
          await Directory.systemTemp.createTemp('takt_4b_restart_');
      final file = File('${dir.path}/takt.sqlite3');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final firstDb = AppDatabase.forTesting(NativeDatabase(file));
      await firstDb.initialize();
      final firstSnapshot = _analysisSnapshot();
      await firstDb.customStatement(
        '''
INSERT INTO competitions (
  id, created_at_epoch_ms, updated_at_epoch_ms
) VALUES (?, ?, ?)
''',
        [firstSnapshot.competitionId, 1, 1],
      );
      await firstDb.customStatement(
        '''
INSERT INTO analysis_snapshots (
  id, competition_id, report_version, assembly_material_fingerprint,
  source_set_fingerprint, wire_fingerprint, report_changed,
  response_json, cached_at_epoch_ms
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
        [
          firstSnapshot.id,
          firstSnapshot.competitionId,
          firstSnapshot.reportVersion,
          firstSnapshot.assemblyMaterialFingerprint,
          null,
          firstSnapshot.wireFingerprint,
          1,
          firstSnapshot.responseJson,
          firstSnapshot.cachedAtEpochMs,
        ],
      );
      final firstEvaluations = DriftEvaluationRepository(firstDb);
      final firstPlans = DriftSavedPlanRepository(firstDb);
      final evaluation = await firstEvaluations.persistEvaluation(
        analysisSnapshot: firstSnapshot,
        evaluationRequestJson: _evaluationRequest(),
        evaluationResponseJson: jsonEncode(decisionFixture()),
        planningWindowPolicyJson: _windowPolicyJson(),
      );
      final revision = await firstPlans.acceptEvaluation(
        evaluationId: evaluation.id,
        candidateId: primaryId,
        selectionSource: SelectionSource.primary,
      );
      final initialDetail = await firstPlans.loadDetail(revision.savedPlanId);
      await firstPlans.updateTaskProgress(
        savedPlanTaskId: initialDetail!.tasks.single.task.id,
        progressPercent: 65,
        actualMinutes: 50,
      );
      await firstDb.close();

      final secondDb = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(secondDb.close);
      await secondDb.initialize();
      final secondPlans = DriftSavedPlanRepository(secondDb);
      final summaries = await secondPlans.listSummaries();

      expect(summaries, hasLength(1));
      final detail = await secondPlans.loadDetail(summaries.single.plan.id);
      expect(detail, isNotNull);
      expect(detail!.summary.currentRevision.id, revision.id);
      expect(detail.tasks.single.progress.progressPercent, 65);
      expect(detail.tasks.single.progress.actualMinutes, 50);
      expect(detail.acceptedCommitments, hasLength(1));
      expect(await secondPlans.activeAcceptedBlocks(), hasLength(1));
    });

    test('database rejects half-formed SUPERSEDED transition', () async {
      final evaluation = await evaluations.persistEvaluation(
        analysisSnapshot: snapshot,
        evaluationRequestJson: _evaluationRequest(),
        evaluationResponseJson: jsonEncode(decisionFixture()),
        planningWindowPolicyJson: _windowPolicyJson(),
      );

      await expectLater(
        db.customStatement(
          '''
INSERT INTO reevaluation_transitions (
  id, prior_evaluation_id, current_evaluation_id, kind,
  transport_request_json, transport_response_json,
  transition_json, error_json, created_at_epoch_ms
) VALUES (?, ?, NULL, 'SUPERSEDED', ?, ?, ?, NULL, ?)
''',
          [
            'broken-transition',
            evaluation.id,
            '{}',
            '{}',
            '{}',
            1,
          ],
        ),
        throwsA(anything),
      );
    });
  });
}

PlanningTaskDraft _task() => PlanningTaskDraft(
      taskId: 'task-draft',
      name: 'Build prototype',
      mandatory: true,
      dependencies: const [],
      effortMinMinutes: 30,
      effortLikelyMinutes: 30,
      effortMaxMinutes: 30,
      assumptions: const ['Single-person work.'],
    );

PlanningPreferences _preferences(String timezone) => PlanningPreferences(
      timezone: timezone,
      maxProjectMinutesPerDay: 240,
      preferredFocusMinutes: 90,
      bufferTargetMinutes: 30,
      updatedAtEpochMs: 1,
    );

ScheduleState _schedule(PlanningPreferences preferences) => ScheduleState(
      commitments: const [],
      recurrenceRules: const [],
      recurrenceExceptions: const [],
      preferences: preferences,
    );

AnalysisSnapshot _analysisSnapshot({
  String deadline = '2026-10-10T16:00:00Z',
}) {
  final reportHash = List.filled(64, 'a').join();
  final body = jsonEncode({
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
            'value': deadline,
            'normalized_value': deadline,
          },
        },
      },
      'ref': {
        'assembly_material_fingerprint': reportHash,
      },
    },
  });
  return AnalysisSnapshot(
    id: 'snapshot-2',
    competitionId: 'competition-1',
    reportVersion: 2,
    assemblyMaterialFingerprint: reportHash,
    sourceSetFingerprint: null,
    wireFingerprint: List.filled(64, 'f').join(),
    reportChanged: true,
    responseJson: body,
    cachedAtEpochMs: 1,
  );
}

String _evaluationRequest() {
  final reportHash = List.filled(64, 'a').join();
  return jsonEncode({
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
        'assembly_material_fingerprint': reportHash,
      },
    },
    'readiness_context': {
      'user': {
        'age': null,
        'student_status': null,
        'country': null,
      },
      'selected_scope': null,
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
          'max_project_minutes_per_day': 240,
          'preferred_focus_minutes': 90,
          'buffer_target_minutes': 30,
        },
      },
    },
  });
}

String _windowPolicyJson() => jsonEncode({
      'policy_version': 'planning-window-policy-v1',
      'timezone': 'Asia/Jakarta',
      'start_local': '08:00',
      'end_local': '22:00',
    });
