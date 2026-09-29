import 'enums.dart';

/// Model REEVALUATION_TRANSITIONS — jejak perpindahan dari satu evaluasi ke
/// evaluasi berikutnya (UNCHANGED = tetap; SUPERSEDED = digantikan).
class ReevaluationTransition {
  ReevaluationTransition({
    required this.id,
    required this.priorEvaluationId,
    this.currentEvaluationId,
    required this.kind,
    required this.transportRequestJson,
    required this.transportResponseJson,
    required this.transitionJson,
    this.errorJson,
    required this.createdAtEpochMs,
  });

  final String id;
  final String priorEvaluationId;

  /// null bila kind == unchanged.
  final String? currentEvaluationId;
  final ReevaluationKind kind;
  final String transportRequestJson;
  final String transportResponseJson;
  final String transitionJson;
  final String? errorJson;
  final int createdAtEpochMs;

  DateTime get createdAt =>
      DateTime.fromMillisecondsSinceEpoch(createdAtEpochMs);

  factory ReevaluationTransition.fromMap(Map<String, Object?> m) =>
      ReevaluationTransition(
        id: m['id']! as String,
        priorEvaluationId: m['prior_evaluation_id']! as String,
        currentEvaluationId: m['current_evaluation_id'] as String?,
        kind: ReevaluationKind.fromWire(m['kind']! as String),
        transportRequestJson: m['transport_request_json']! as String,
        transportResponseJson: m['transport_response_json']! as String,
        transitionJson: m['transition_json']! as String,
        errorJson: m['error_json'] as String?,
        createdAtEpochMs: m['created_at_epoch_ms']! as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'prior_evaluation_id': priorEvaluationId,
        'current_evaluation_id': currentEvaluationId,
        'kind': kind.wire,
        'transport_request_json': transportRequestJson,
        'transport_response_json': transportResponseJson,
        'transition_json': transitionJson,
        'error_json': errorJson,
        'created_at_epoch_ms': createdAtEpochMs,
      };
}
