import 'enums.dart';

/// Model EVALUATIONS — hasil evaluasi kesiapan & kelayakan sebuah kompetisi
/// terhadap satu analysis snapshot.
class Evaluation {
  Evaluation({
    required this.id,
    required this.competitionId,
    required this.analysisSnapshotId,
    required this.evaluatedAtEpochMs,
    required this.requestJson,
    required this.responseJson,
    required this.planningWindowPolicyJson,
    required this.evaluationBasisFingerprint,
    required this.readinessStatus,
    this.feasibilityStatus,
    required this.createdAtEpochMs,
  });

  final String id;
  final String competitionId;
  final String analysisSnapshotId;
  final int evaluatedAtEpochMs;
  final String requestJson;
  final String responseJson;
  final String planningWindowPolicyJson;
  final String evaluationBasisFingerprint;
  final ReadinessStatus readinessStatus;

  /// Boleh null (belum dinilai kelayakannya).
  final FeasibilityStatus? feasibilityStatus;

  final int createdAtEpochMs;

  DateTime get evaluatedAt =>
      DateTime.fromMillisecondsSinceEpoch(evaluatedAtEpochMs);

  factory Evaluation.fromMap(Map<String, Object?> m) => Evaluation(
        id: m['id']! as String,
        competitionId: m['competition_id']! as String,
        analysisSnapshotId: m['analysis_snapshot_id']! as String,
        evaluatedAtEpochMs: m['evaluated_at_epoch_ms']! as int,
        requestJson: m['request_json']! as String,
        responseJson: m['response_json']! as String,
        planningWindowPolicyJson:
            m['planning_window_policy_json']! as String,
        evaluationBasisFingerprint:
            m['evaluation_basis_fingerprint']! as String,
        readinessStatus:
            ReadinessStatus.fromWire(m['readiness_status']! as String),
        feasibilityStatus:
            FeasibilityStatus.fromWire(m['feasibility_status'] as String?),
        createdAtEpochMs: m['created_at_epoch_ms']! as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'competition_id': competitionId,
        'analysis_snapshot_id': analysisSnapshotId,
        'evaluated_at_epoch_ms': evaluatedAtEpochMs,
        'request_json': requestJson,
        'response_json': responseJson,
        'planning_window_policy_json': planningWindowPolicyJson,
        'evaluation_basis_fingerprint': evaluationBasisFingerprint,
        'readiness_status': readinessStatus.wire,
        'feasibility_status': feasibilityStatus?.wire,
        'created_at_epoch_ms': createdAtEpochMs,
      };
}
