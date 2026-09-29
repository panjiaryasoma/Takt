import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../models/analysis_snapshot.dart';
import '../../models/enums.dart';
import '../../models/evaluation.dart';
import '../../models/plan_evaluation_wire.dart';
import '../../models/planning_input_draft.dart';
import '../../models/reevaluation_transition.dart';
import '../../models/reevaluation_wire.dart';
import '../../utils/deterministic_json.dart';
import '../database/app_database.dart';
import 'evaluation_repository.dart';

final class EvaluationIntegrityException implements Exception {
  const EvaluationIntegrityException(this.message);
  final String message;

  @override
  String toString() => 'EVALUATION_INTEGRITY_CONFLICT: $message';
}

final class DriftEvaluationRepository implements EvaluationRepository {
  DriftEvaluationRepository(
    this._db, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;
  bool _initialized = false;
  bool _closed = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _db.initialize();
    _initialized = true;
  }

  @override
  Future<Evaluation?> evaluationById(String evaluationId) async {
    await initialize();
    final rows = await _db.customSelect(
      'SELECT * FROM evaluations WHERE id = ?',
      variables: [Variable<String>(evaluationId)],
    ).get();
    return rows.isEmpty ? null : Evaluation.fromMap(rows.single.data);
  }

  @override
  Future<Evaluation> persistEvaluation({
    required AnalysisSnapshot analysisSnapshot,
    required String evaluationRequestJson,
    required String evaluationResponseJson,
    required String planningWindowPolicyJson,
  }) async {
    await initialize();
    return _db.transaction(
      () => _persistEvaluationInTransaction(
        analysisSnapshot: analysisSnapshot,
        evaluationRequestJson: evaluationRequestJson,
        evaluationResponseJson: evaluationResponseJson,
        planningWindowPolicyJson: planningWindowPolicyJson,
      ),
    );
  }

  Future<Evaluation> _persistEvaluationInTransaction({
    required AnalysisSnapshot analysisSnapshot,
    required String evaluationRequestJson,
    required String evaluationResponseJson,
    required String planningWindowPolicyJson,
  }) async {
    final response = PlanEvaluateResponseV1.parse(evaluationResponseJson);
    final request = _jsonObject(evaluationRequestJson, 'evaluation request');
    final reportBundle = _object(request['report_bundle'], 'report_bundle');
    final report = _object(reportBundle['report'], 'report_bundle.report');
    final ref = _object(reportBundle['ref'], 'report_bundle.ref');

    final requestCompetition = report['competition_id'];
    final requestVersion = report['report_version'];
    final requestFingerprint = ref['assembly_material_fingerprint'];
    if (requestCompetition != analysisSnapshot.competitionId ||
        requestVersion != analysisSnapshot.reportVersion ||
        requestFingerprint != analysisSnapshot.assemblyMaterialFingerprint ||
        response.basis.report.competitionId != analysisSnapshot.competitionId ||
        response.basis.report.reportVersion != analysisSnapshot.reportVersion ||
        response.basis.report.assemblyMaterialFingerprint !=
            analysisSnapshot.assemblyMaterialFingerprint) {
      throw const EvaluationIntegrityException(
        'request, analysis snapshot and evaluation response do not share one report identity',
      );
    }

    final policy = _jsonObject(
      planningWindowPolicyJson,
      'planning window policy',
    );
    final parsedPolicy = PlanningWindowPolicyV1.fromJson(policy);
    final planning = _object(request['planning'], 'planning');
    final availability =
        _object(planning['availability'], 'planning.availability');
    final preferences =
        _object(availability['preferences'], 'planning.availability.preferences');
    if (preferences['timezone'] != parsedPolicy.timezone) {
      throw const EvaluationIntegrityException(
        'planning window policy timezone must match evaluated planning preferences',
      );
    }

    final evaluation = Evaluation(
      id: response.evaluationId,
      competitionId: response.basis.report.competitionId,
      analysisSnapshotId: analysisSnapshot.id,
      evaluatedAtEpochMs: response.evaluatedAt.millisecondsSinceEpoch,
      requestJson: evaluationRequestJson,
      responseJson: evaluationResponseJson,
      planningWindowPolicyJson: planningWindowPolicyJson,
      evaluationBasisFingerprint: response.basis.fingerprint,
      readinessStatus: response.readiness.status,
      feasibilityStatus: response.planning?.feasibility,
      createdAtEpochMs: _now().millisecondsSinceEpoch,
    );

    final existing = await _evaluationByIdInternal(evaluation.id);
    if (existing != null) {
      if (!_sameEvaluationMaterial(existing, evaluation)) {
        throw const EvaluationIntegrityException(
          'evaluation_id already exists with different persisted material',
        );
      }
      return existing;
    }

    await _db.customStatement(
      '''
INSERT INTO evaluations (
  id, competition_id, analysis_snapshot_id, evaluated_at_epoch_ms,
  request_json, response_json, planning_window_policy_json,
  evaluation_basis_fingerprint, readiness_status, feasibility_status,
  created_at_epoch_ms
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
      [
        evaluation.id,
        evaluation.competitionId,
        evaluation.analysisSnapshotId,
        evaluation.evaluatedAtEpochMs,
        evaluation.requestJson,
        evaluation.responseJson,
        evaluation.planningWindowPolicyJson,
        evaluation.evaluationBasisFingerprint,
        evaluation.readinessStatus.wire,
        evaluation.feasibilityStatus?.wire,
        evaluation.createdAtEpochMs,
      ],
    );
    return evaluation;
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
  }) async {
    await initialize();
    if (transition.priorEvaluationId != priorEvaluationId) {
      throw const EvaluationIntegrityException(
        'transition prior evaluation does not match requested prior evaluation',
      );
    }
    if (transportRequestJson.trim().isEmpty ||
        transportResponseJson.trim().isEmpty) {
      throw const EvaluationIntegrityException(
        'trusted re-evaluation transition requires exact transport material',
      );
    }

    return _db.transaction(() async {
      final prior = await _evaluationByIdInternal(priorEvaluationId);
      if (prior == null) {
        throw const EvaluationIntegrityException(
          'prior evaluation must exist before persisting a transition',
        );
      }
      if (prior.evaluationBasisFingerprint !=
          transition.priorBasisFingerprint) {
        throw const EvaluationIntegrityException(
          'transition prior basis does not match persisted evaluation',
        );
      }

      Evaluation? current;
      if (transition.kind == ReevaluationKind.unchanged) {
        if (errorJson != null ||
            currentAnalysisSnapshot != null ||
            currentEvaluationRequestJson != null ||
            currentEvaluationResponseJson != null ||
            planningWindowPolicyJson != null) {
          throw const EvaluationIntegrityException(
            'UNCHANGED transition cannot persist a fresh evaluation or error',
          );
        }
      } else if (errorJson != null) {
        if (currentAnalysisSnapshot != null ||
            currentEvaluationRequestJson != null ||
            currentEvaluationResponseJson != null ||
            planningWindowPolicyJson != null ||
            transition.currentBasisFingerprint != null) {
          throw const EvaluationIntegrityException(
            'failed SUPERSEDED transition cannot persist a fresh evaluation',
          );
        }
        _jsonObject(errorJson, 're-evaluation error');
      } else {
        if (currentAnalysisSnapshot == null ||
            currentEvaluationRequestJson == null ||
            currentEvaluationResponseJson == null ||
            planningWindowPolicyJson == null ||
            transition.currentBasisFingerprint == null) {
          throw const EvaluationIntegrityException(
            'successful SUPERSEDED transition requires a complete fresh evaluation',
          );
        }
        current = await _persistEvaluationInTransaction(
          analysisSnapshot: currentAnalysisSnapshot,
          evaluationRequestJson: currentEvaluationRequestJson,
          evaluationResponseJson: currentEvaluationResponseJson,
          planningWindowPolicyJson: planningWindowPolicyJson,
        );
        if (current.evaluationBasisFingerprint !=
            transition.currentBasisFingerprint) {
          throw const EvaluationIntegrityException(
            'transition current basis does not match fresh evaluation',
          );
        }
      }

      final transitionJson = deterministicJsonEncode(transition.toJson());
      final id = _transitionId(
        priorEvaluationId,
        transportRequestJson,
        transportResponseJson,
      );
      final row = ReevaluationTransition(
        id: id,
        priorEvaluationId: priorEvaluationId,
        currentEvaluationId: current?.id,
        kind: transition.kind,
        transportRequestJson: transportRequestJson,
        transportResponseJson: transportResponseJson,
        transitionJson: transitionJson,
        errorJson: errorJson,
        createdAtEpochMs: _now().millisecondsSinceEpoch,
      );

      final existing = await _transitionByIdInternal(id);
      if (existing != null) {
        if (!_sameTransitionMaterial(existing, row)) {
          throw const EvaluationIntegrityException(
            're-evaluation transport identity already exists with different material',
          );
        }
        return ReevaluationPersistenceResult(
          transition: existing,
          evaluation: current,
        );
      }

      await _db.customStatement(
        '''
INSERT INTO reevaluation_transitions (
  id, prior_evaluation_id, current_evaluation_id, kind,
  transport_request_json, transport_response_json,
  transition_json, error_json, created_at_epoch_ms
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
        [
          row.id,
          row.priorEvaluationId,
          row.currentEvaluationId,
          row.kind.wire,
          row.transportRequestJson,
          row.transportResponseJson,
          row.transitionJson,
          row.errorJson,
          row.createdAtEpochMs,
        ],
      );
      return ReevaluationPersistenceResult(
        transition: row,
        evaluation: current,
      );
    });
  }

  @override
  Future<bool> isStale(String evaluationId) async {
    await initialize();
    final row = await _db.customSelect(
      '''
SELECT EXISTS(
  SELECT 1 FROM reevaluation_transitions
  WHERE prior_evaluation_id = ? AND kind = 'SUPERSEDED'
) AS stale
''',
      variables: [Variable<String>(evaluationId)],
    ).getSingle();
    return row.data['stale'] == 1;
  }

  Future<Evaluation?> _evaluationByIdInternal(String id) async {
    final rows = await _db.customSelect(
      'SELECT * FROM evaluations WHERE id = ?',
      variables: [Variable<String>(id)],
    ).get();
    return rows.isEmpty ? null : Evaluation.fromMap(rows.single.data);
  }

  Future<ReevaluationTransition?> _transitionByIdInternal(String id) async {
    final rows = await _db.customSelect(
      'SELECT * FROM reevaluation_transitions WHERE id = ?',
      variables: [Variable<String>(id)],
    ).get();
    return rows.isEmpty
        ? null
        : ReevaluationTransition.fromMap(rows.single.data);
  }

  static bool _sameEvaluationMaterial(Evaluation a, Evaluation b) {
    return a.id == b.id &&
        a.competitionId == b.competitionId &&
        a.analysisSnapshotId == b.analysisSnapshotId &&
        a.evaluatedAtEpochMs == b.evaluatedAtEpochMs &&
        a.requestJson == b.requestJson &&
        a.responseJson == b.responseJson &&
        a.planningWindowPolicyJson == b.planningWindowPolicyJson &&
        a.evaluationBasisFingerprint == b.evaluationBasisFingerprint &&
        a.readinessStatus == b.readinessStatus &&
        a.feasibilityStatus == b.feasibilityStatus;
  }

  static bool _sameTransitionMaterial(
    ReevaluationTransition a,
    ReevaluationTransition b,
  ) {
    return a.priorEvaluationId == b.priorEvaluationId &&
        a.currentEvaluationId == b.currentEvaluationId &&
        a.kind == b.kind &&
        a.transportRequestJson == b.transportRequestJson &&
        a.transportResponseJson == b.transportResponseJson &&
        a.transitionJson == b.transitionJson &&
        a.errorJson == b.errorJson;
  }

  static Map<String, dynamic> _jsonObject(String raw, String field) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('not object');
      }
      return Map<String, dynamic>.from(decoded);
    } on Object catch (error) {
      throw EvaluationIntegrityException(
        '$field is not a valid JSON object: $error',
      );
    }
  }

  static Map<String, dynamic> _object(Object? value, String field) {
    if (value is! Map) {
      throw EvaluationIntegrityException('$field must be an object');
    }
    return Map<String, dynamic>.from(value);
  }

  static String _transitionId(
    String priorEvaluationId,
    String request,
    String response,
  ) {
    final digest =
        sha256.convert(utf8.encode('$request\n$response')).toString();
    return 'reeval-$priorEvaluationId-${digest.substring(0, 20)}';
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _db.close();
  }
}
