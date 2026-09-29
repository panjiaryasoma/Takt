import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/accepted_commitment.dart';
import '../../models/active_accepted_block.dart';
import '../../models/enums.dart';
import '../../models/evaluation.dart';
import '../../models/plan_evaluation_wire.dart';
import '../../models/planning_input_draft.dart';
import '../../models/saved_plan.dart';
import '../../models/saved_plan_revision.dart';
import '../../models/saved_plan_task.dart';
import '../../models/task_progress.dart';
import '../../utils/deterministic_json.dart';
import '../database/app_database.dart';
import 'saved_plan_repository.dart';

final class SavedPlanIntegrityException implements Exception {
  const SavedPlanIntegrityException(this.message);
  final String message;

  @override
  String toString() => 'SAVED_PLAN_INTEGRITY_CONFLICT: $message';
}

final class DriftSavedPlanRepository implements SavedPlanRepository {
  DriftSavedPlanRepository(
    this._db, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;
  final StreamController<List<SavedPlanSummary>> _changes =
      StreamController<List<SavedPlanSummary>>.broadcast();

  bool _initialized = false;
  bool _closed = false;
  List<SavedPlanSummary> _current = const [];

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _db.initialize();
    _initialized = true;
    _current = await _listSummariesInternal();
  }

  @override
  Stream<List<SavedPlanSummary>> watchSummaries() async* {
    await initialize();
    yield List.unmodifiable(_current);
    yield* _changes.stream;
  }

  @override
  Future<List<SavedPlanSummary>> listSummaries() async {
    await initialize();
    _current = await _listSummariesInternal();
    return List.unmodifiable(_current);
  }

  @override
  Future<SavedPlan?> planForCompetition(String competitionId) async {
    await initialize();
    final rows = await _db.customSelect(
      'SELECT * FROM saved_plans WHERE competition_id = ?',
      variables: [Variable<String>(competitionId)],
    ).get();
    return rows.isEmpty ? null : SavedPlan.fromMap(rows.single.data);
  }

  @override
  Future<SavedPlanRevision> acceptEvaluation({
    required String evaluationId,
    required String candidateId,
    required SelectionSource selectionSource,
  }) async {
    await initialize();
    final result = await _db.transaction(() async {
      final evaluation = await _evaluationById(evaluationId);
      if (evaluation == null) {
        throw const SavedPlanIntegrityException(
          'accepted evaluation must already be persisted',
        );
      }

      final response = PlanEvaluateResponseV1.parse(evaluation.responseJson);
      if (response.evaluationId != evaluation.id ||
          response.basis.report.competitionId != evaluation.competitionId) {
        throw const SavedPlanIntegrityException(
          'persisted evaluation identity is inconsistent',
        );
      }

      final planning = response.planning;
      if (planning == null ||
          !planning.allowedActions.contains(RecommendationAction.accept)) {
        throw const SavedPlanIntegrityException(
          'persisted evaluation does not authorize ACCEPT',
        );
      }
      final candidate = planning.candidate(candidateId);
      if (candidate == null) {
        throw const SavedPlanIntegrityException(
          'selected candidate does not belong to the persisted evaluation',
        );
      }

      final recommendation = planning.recommendation;
      if (recommendation == null) {
        throw const SavedPlanIntegrityException(
          'accepted evaluation has no recommendation set',
        );
      }
      final primaryId = recommendation.primaryCandidate.candidateId;
      final alternativeIds = recommendation.alternativeCandidates
          .map((item) => item.candidateId)
          .toSet();
      if (selectionSource == SelectionSource.primary &&
              candidateId != primaryId ||
          selectionSource == SelectionSource.alternative &&
              !alternativeIds.contains(candidateId)) {
        throw const SavedPlanIntegrityException(
          'candidate selection source does not match backend recommendation',
        );
      }

      final priorRows = await _db.customSelect(
        'SELECT * FROM saved_plan_revisions WHERE evaluation_id = ?',
        variables: [Variable<String>(evaluationId)],
      ).get();
      if (priorRows.isNotEmpty) {
        final existing = SavedPlanRevision.fromMap(priorRows.single.data);
        if (existing.selectedCandidateId == candidateId &&
            existing.selectionSource == selectionSource) {
          return existing;
        }
        throw const SavedPlanIntegrityException(
          'one evaluation cannot produce two different accepted decisions',
        );
      }

      final request = _jsonObject(evaluation.requestJson, 'evaluation request');
      final planningRequest = _object(request['planning'], 'planning');
      final workload = _object(planningRequest['workload'], 'planning.workload');
      final taskValues = workload['tasks'];
      if (taskValues is! List || taskValues.isEmpty) {
        throw const SavedPlanIntegrityException(
          'persisted evaluation workload must contain tasks',
        );
      }
      final tasks = <PlanningTaskDraft>[];
      final rawTasks = <Map<String, dynamic>>[];
      for (final value in taskValues) {
        final raw = _object(value, 'planning.workload.tasks[]');
        rawTasks.add(raw);
        tasks.add(PlanningTaskDraft.fromWire(raw));
      }
      _validateTaskGraph(tasks);

      final rawResponse =
          _jsonObject(evaluation.responseJson, 'evaluation response');
      final rawCandidate =
          _findRawCandidate(rawResponse, candidateId, evaluationId);
      final rawBlocks = rawCandidate['work_blocks'];
      if (rawBlocks is! List ||
          rawBlocks.length != candidate.workBlocks.length) {
        throw const SavedPlanIntegrityException(
          'persisted candidate block projection is inconsistent',
        );
      }

      final nowMs = _now().millisecondsSinceEpoch;
      var plan = await _planForCompetitionInternal(evaluation.competitionId);
      if (plan == null) {
        plan = SavedPlan(
          id: 'plan-${evaluation.competitionId}',
          competitionId: evaluation.competitionId,
          createdAtEpochMs: nowMs,
          updatedAtEpochMs: nowMs,
        );
        await _db.customStatement(
          '''
INSERT INTO saved_plans (
  id, competition_id, created_at_epoch_ms, updated_at_epoch_ms
) VALUES (?, ?, ?, ?)
''',
          [
            plan.id,
            plan.competitionId,
            plan.createdAtEpochMs,
            plan.updatedAtEpochMs,
          ],
        );
      }

      final parent = await _currentRevisionInternal(plan.id);
      final revisionNumber = (parent?.revisionNumber ?? 0) + 1;
      final revision = SavedPlanRevision(
        id: 'revision-${evaluation.id}',
        savedPlanId: plan.id,
        revisionNumber: revisionNumber,
        evaluationId: evaluation.id,
        selectedCandidateId: candidateId,
        selectionSource: selectionSource,
        supersedesRevisionId: parent?.id,
        acceptedAtEpochMs: nowMs,
      );
      await _db.customStatement(
        '''
INSERT INTO saved_plan_revisions (
  id, saved_plan_id, revision_number, evaluation_id,
  selected_candidate_id, selection_source, supersedes_revision_id,
  accepted_at_epoch_ms
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
''',
        [
          revision.id,
          revision.savedPlanId,
          revision.revisionNumber,
          revision.evaluationId,
          revision.selectedCandidateId,
          revision.selectionSource.wire,
          revision.supersedesRevisionId,
          revision.acceptedAtEpochMs,
        ],
      );

      final savedTaskIds = <String, String>{};
      for (var index = 0; index < tasks.length; index++) {
        final task = tasks[index];
        final taskId = 'task-${revision.id}-$index';
        savedTaskIds[task.taskId] = taskId;
        await _db.customStatement(
          '''
INSERT INTO saved_plan_tasks (
  id, saved_plan_revision_id, domain_task_id, ordinal, name, mandatory,
  effort_min_minutes, effort_likely_minutes, effort_max_minutes,
  dependencies_json, assumptions_json, task_payload_json
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
          [
            taskId,
            revision.id,
            task.taskId,
            index,
            task.name,
            task.mandatory ? 1 : 0,
            task.effortMinMinutes,
            task.effortLikelyMinutes,
            task.effortMaxMinutes,
            deterministicJsonEncode(task.dependencies),
            deterministicJsonEncode(task.assumptions),
            deterministicJsonEncode(rawTasks[index]),
          ],
        );
        await _db.customStatement(
          '''
INSERT INTO task_progress (
  saved_plan_task_id, progress_percent, actual_minutes, updated_at_epoch_ms
) VALUES (?, 0, NULL, ?)
''',
          [taskId, nowMs],
        );
      }

      for (var index = 0; index < candidate.workBlocks.length; index++) {
        final block = candidate.workBlocks[index];
        final savedTaskId = savedTaskIds[block.taskId];
        if (savedTaskId == null) {
          throw SavedPlanIntegrityException(
            'candidate references unknown workload task ${block.taskId}',
          );
        }
        final rawBlock = _object(
          rawBlocks[index],
          'candidate.work_blocks[$index]',
        );
        if (rawBlock['task_id'] != block.taskId) {
          throw const SavedPlanIntegrityException(
            'candidate raw and parsed work-block order disagree',
          );
        }
        await _db.customStatement(
          '''
INSERT INTO accepted_commitments (
  id, saved_plan_revision_id, saved_plan_task_id, source_block_ordinal,
  start_at_epoch_ms, end_at_epoch_ms, allocated_minutes,
  original_availability_source, source_block_json, accepted_at_epoch_ms
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
          [
            'accepted-${revision.id}-$index',
            revision.id,
            savedTaskId,
            index,
            block.start.millisecondsSinceEpoch,
            block.end.millisecondsSinceEpoch,
            block.allocatedMinutes,
            block.availabilitySource,
            deterministicJsonEncode(rawBlock),
            nowMs,
          ],
        );
      }

      await _db.customStatement(
        'UPDATE saved_plans SET updated_at_epoch_ms = ? WHERE id = ?',
        [nowMs, plan.id],
      );
      return revision;
    });

    try {
      await refresh();
    } on Object {
      // The Accept transaction is already durable. Read-model refresh is
      // best-effort and must not turn a committed decision into a false failure.
    }
    return result;
  }

  @override
  Future<List<ActiveAcceptedBlock>> activeAcceptedBlocks({
    String? excludingSavedPlanId,
  }) async {
    await initialize();
    final where = excludingSavedPlanId == null
        ? ''
        : 'AND p.id <> ?';
    final variables = excludingSavedPlanId == null
        ? const <Variable>[]
        : <Variable>[Variable<String>(excludingSavedPlanId)];
    final rows = await _db.customSelect(
      '''
SELECT
  p.id AS saved_plan_id,
  p.competition_id,
  r.id AS saved_plan_revision_id,
  a.id AS accepted_commitment_id,
  a.start_at_epoch_ms,
  a.end_at_epoch_ms,
  t.name AS task_name
FROM saved_plans p
JOIN saved_plan_revisions r ON r.saved_plan_id = p.id
JOIN accepted_commitments a ON a.saved_plan_revision_id = r.id
JOIN saved_plan_tasks t ON t.id = a.saved_plan_task_id
WHERE NOT EXISTS (
  SELECT 1 FROM saved_plan_revisions successor
  WHERE successor.supersedes_revision_id = r.id
)
$where
ORDER BY a.start_at_epoch_ms, p.id, a.source_block_ordinal
''',
      variables: variables,
    ).get();

    return rows
        .map(
          (row) => ActiveAcceptedBlock(
            savedPlanId: row.data['saved_plan_id']! as String,
            savedPlanRevisionId:
                row.data['saved_plan_revision_id']! as String,
            acceptedCommitmentId:
                row.data['accepted_commitment_id']! as String,
            competitionId: row.data['competition_id']! as String,
            taskName: row.data['task_name']! as String,
            startAtEpochMs: row.data['start_at_epoch_ms']! as int,
            endAtEpochMs: row.data['end_at_epoch_ms']! as int,
            source:
                'saved-plan:${row.data['saved_plan_id']! as String}',
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<SavedPlanDetail?> loadDetail(String savedPlanId) async {
    await initialize();
    final summaries = await _listSummariesInternal();
    SavedPlanSummary? summary;
    for (final item in summaries) {
      if (item.plan.id == savedPlanId) {
        summary = item;
        break;
      }
    }
    if (summary == null) return null;

    final revisionRows = await _db.customSelect(
      '''
SELECT * FROM saved_plan_revisions
WHERE saved_plan_id = ?
ORDER BY revision_number DESC
''',
      variables: [Variable<String>(savedPlanId)],
    ).get();
    final revisions = revisionRows
        .map((row) => SavedPlanRevision.fromMap(row.data))
        .toList(growable: false);

    final taskRows = await _db.customSelect(
      '''
SELECT t.*, p.progress_percent, p.actual_minutes, p.updated_at_epoch_ms
FROM saved_plan_tasks t
JOIN task_progress p ON p.saved_plan_task_id = t.id
WHERE t.saved_plan_revision_id = ?
ORDER BY t.ordinal
''',
      variables: [Variable<String>(summary.currentRevision.id)],
    ).get();
    final tasks = [
      for (final row in taskRows)
        SavedPlanTaskState(
          task: SavedPlanTask.fromMap(row.data),
          progress: TaskProgress(
            savedPlanTaskId: row.data['id']! as String,
            progressPercent: row.data['progress_percent']! as int,
            actualMinutes: row.data['actual_minutes'] as int?,
            updatedAtEpochMs: row.data['updated_at_epoch_ms']! as int,
          ),
        ),
    ];

    final acceptedRows = await _db.customSelect(
      '''
SELECT * FROM accepted_commitments
WHERE saved_plan_revision_id = ?
ORDER BY source_block_ordinal
''',
      variables: [Variable<String>(summary.currentRevision.id)],
    ).get();

    return SavedPlanDetail(
      summary: summary,
      revisions: List.unmodifiable(revisions),
      tasks: List.unmodifiable(tasks),
      acceptedCommitments: List.unmodifiable(
        acceptedRows.map((row) => AcceptedCommitment.fromMap(row.data)),
      ),
    );
  }

  @override
  Future<void> updateTaskProgress({
    required String savedPlanTaskId,
    required int progressPercent,
    int? actualMinutes,
    bool clearActualMinutes = false,
  }) async {
    await initialize();
    if (progressPercent < 0 ||
        progressPercent > 100 ||
        actualMinutes != null && actualMinutes < 0) {
      throw const SavedPlanIntegrityException(
        'task progress values are outside the allowed range',
      );
    }
    final rows = await _db.customSelect(
      'SELECT actual_minutes FROM task_progress WHERE saved_plan_task_id = ?',
      variables: [Variable<String>(savedPlanTaskId)],
    ).get();
    if (rows.isEmpty) {
      throw const SavedPlanIntegrityException(
        'task progress row does not exist',
      );
    }
    final previous = rows.single.data['actual_minutes'] as int?;
    final nextActual = clearActualMinutes ? null : (actualMinutes ?? previous);
    await _db.customStatement(
      '''
UPDATE task_progress
SET progress_percent = ?, actual_minutes = ?, updated_at_epoch_ms = ?
WHERE saved_plan_task_id = ?
''',
      [
        progressPercent,
        nextActual,
        _now().millisecondsSinceEpoch,
        savedPlanTaskId,
      ],
    );
    await refresh();
  }

  @override
  Future<void> refresh() async {
    await initialize();
    _current = await _listSummariesInternal();
    if (!_changes.isClosed) {
      _changes.add(List.unmodifiable(_current));
    }
  }

  Future<List<SavedPlanSummary>> _listSummariesInternal() async {
    final rows = await _db.customSelect(
      '''
SELECT p.*, r.id AS revision_id
FROM saved_plans p
JOIN saved_plan_revisions r ON r.saved_plan_id = p.id
WHERE NOT EXISTS (
  SELECT 1 FROM saved_plan_revisions successor
  WHERE successor.supersedes_revision_id = r.id
)
ORDER BY p.updated_at_epoch_ms DESC, p.id
''',
    ).get();

    final output = <SavedPlanSummary>[];
    for (final row in rows) {
      final plan = SavedPlan.fromMap(row.data);
      final revision = await _revisionById(row.data['revision_id']! as String);
      if (revision == null) {
        throw const SavedPlanIntegrityException(
          'saved plan current revision disappeared',
        );
      }
      final evaluation = await _evaluationById(revision.evaluationId);
      if (evaluation == null) {
        throw const SavedPlanIntegrityException(
          'saved plan revision references a missing evaluation',
        );
      }
      final request = _jsonObject(evaluation.requestJson, 'evaluation request');
      final reportBundle = _object(request['report_bundle'], 'report_bundle');
      final report = _object(reportBundle['report'], 'report');
      final fields = _object(report['canonical_fields'], 'canonical_fields');
      final title = _canonicalText(fields['competition_name']) ??
          plan.competitionId;
      final deadlineText = _canonicalText(fields['submission_deadline']);
      final deadline =
          deadlineText == null ? null : DateTime.tryParse(deadlineText);
      if (deadline == null) {
        throw const SavedPlanIntegrityException(
          'accepted plan has no usable submission deadline',
        );
      }
      final staleRow = await _db.customSelect(
        '''
SELECT EXISTS(
  SELECT 1 FROM reevaluation_transitions
  WHERE prior_evaluation_id = ? AND kind = 'SUPERSEDED'
) AS stale
''',
        variables: [Variable<String>(revision.evaluationId)],
      ).getSingle();

      output.add(
        SavedPlanSummary(
          plan: plan,
          currentRevision: revision,
          title: title,
          deadline: deadline,
          stale: staleRow.data['stale'] == 1,
        ),
      );
    }
    return output;
  }

  Future<SavedPlan?> _planForCompetitionInternal(String competitionId) async {
    final rows = await _db.customSelect(
      'SELECT * FROM saved_plans WHERE competition_id = ?',
      variables: [Variable<String>(competitionId)],
    ).get();
    return rows.isEmpty ? null : SavedPlan.fromMap(rows.single.data);
  }

  Future<SavedPlanRevision?> _currentRevisionInternal(
    String savedPlanId,
  ) async {
    final rows = await _db.customSelect(
      '''
SELECT r.* FROM saved_plan_revisions r
WHERE r.saved_plan_id = ?
AND NOT EXISTS (
  SELECT 1 FROM saved_plan_revisions successor
  WHERE successor.supersedes_revision_id = r.id
)
''',
      variables: [Variable<String>(savedPlanId)],
    ).get();
    if (rows.length > 1) {
      throw const SavedPlanIntegrityException(
        'saved plan has more than one current revision',
      );
    }
    return rows.isEmpty ? null : SavedPlanRevision.fromMap(rows.single.data);
  }

  Future<SavedPlanRevision?> _revisionById(String id) async {
    final rows = await _db.customSelect(
      'SELECT * FROM saved_plan_revisions WHERE id = ?',
      variables: [Variable<String>(id)],
    ).get();
    return rows.isEmpty
        ? null
        : SavedPlanRevision.fromMap(rows.single.data);
  }

  Future<Evaluation?> _evaluationById(String id) async {
    final rows = await _db.customSelect(
      'SELECT * FROM evaluations WHERE id = ?',
      variables: [Variable<String>(id)],
    ).get();
    return rows.isEmpty ? null : Evaluation.fromMap(rows.single.data);
  }

  static Map<String, dynamic> _findRawCandidate(
    Map<String, dynamic> response,
    String candidateId,
    String evaluationId,
  ) {
    final planning = _object(response['planning'], 'response.planning');
    final candidates = planning['candidates'];
    if (candidates is! List) {
      throw const SavedPlanIntegrityException(
        'persisted response candidate pool is invalid',
      );
    }
    Map<String, dynamic>? match;
    for (final value in candidates) {
      final candidate = _object(value, 'response.planning.candidates[]');
      final ref = _object(candidate['ref'], 'candidate.ref');
      if (ref['candidate_id'] == candidateId) {
        if (ref['evaluation_id'] != evaluationId || match != null) {
          throw const SavedPlanIntegrityException(
            'persisted candidate identity is ambiguous',
          );
        }
        match = candidate;
      }
    }
    if (match == null) {
      throw const SavedPlanIntegrityException(
        'persisted raw response does not contain selected candidate',
      );
    }
    return match;
  }

  static String? _canonicalText(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    if (map['state'] != 'VERIFIED' && map['state'] != 'SINGLE_SOURCE') {
      return null;
    }
    final normalized = map['normalized_value'] ?? map['value'];
    if (normalized is! String || normalized.trim().isEmpty) return null;
    return normalized;
  }

  static void _validateTaskGraph(List<PlanningTaskDraft> tasks) {
    final ids = tasks.map((task) => task.taskId).toSet();
    if (ids.length != tasks.length) {
      throw const SavedPlanIntegrityException(
        'persisted workload contains duplicate task IDs',
      );
    }
    for (final task in tasks) {
      if (task.dependencies.any((dependency) => !ids.contains(dependency))) {
        throw const SavedPlanIntegrityException(
          'persisted workload references an unknown task dependency',
        );
      }
    }
    final byId = {for (final task in tasks) task.taskId: task};
    final visiting = <String>{};
    final visited = <String>{};
    bool visit(String id) {
      if (visiting.contains(id)) return false;
      if (visited.contains(id)) return true;
      visiting.add(id);
      for (final dependency in byId[id]!.dependencies) {
        if (!visit(dependency)) return false;
      }
      visiting.remove(id);
      visited.add(id);
      return true;
    }
    if (ids.any((id) => !visit(id))) {
      throw const SavedPlanIntegrityException(
        'persisted workload dependency graph is cyclic',
      );
    }
  }

  static Map<String, dynamic> _jsonObject(String raw, String field) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('not object');
      return Map<String, dynamic>.from(decoded);
    } on Object catch (error) {
      throw SavedPlanIntegrityException(
        '$field is not a valid JSON object: $error',
      );
    }
  }

  static Map<String, dynamic> _object(Object? value, String field) {
    if (value is! Map) {
      throw SavedPlanIntegrityException('$field must be an object');
    }
    return Map<String, dynamic>.from(value);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _changes.close();
    await _db.close();
  }
}
