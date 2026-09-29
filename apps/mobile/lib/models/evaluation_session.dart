import 'plan_evaluation_wire.dart';

/// Host-owned snapshot. The 4B host must pair/validate request, response and
/// analysis snapshot before publication, and discard late request generations.
/// The component carries validated evaluation snapshots; transport wrappers remain host-owned.
final class EvaluationSession {
  EvaluationSession._({
    required this.sessionId,
    required this.generation,
    required this.inputRevision,
    required this.analysisSnapshotId,
    required this.evaluationRequestJson,
    required this.evaluationResponseJson,
  }) : parsedResponse = PlanEvaluateResponseV1.parse(evaluationResponseJson);

  factory EvaluationSession.fromEvaluationSnapshot({
    required String sessionId,
    required int generation,
    required int inputRevision,
    required String analysisSnapshotId,
    required String evaluationRequestJson,
    required String evaluationResponseJson,
  }) {
    if (sessionId.trim().isEmpty || analysisSnapshotId.trim().isEmpty ||
        evaluationRequestJson.trim().isEmpty || generation < 0 || inputRevision < 0) {
      throw const FormatException('Invalid evaluation session metadata');
    }
    return EvaluationSession._(
      sessionId: sessionId,
      generation: generation,
      inputRevision: inputRevision,
      analysisSnapshotId: analysisSnapshotId,
      evaluationRequestJson: evaluationRequestJson,
      evaluationResponseJson: evaluationResponseJson,
    );
  }

  final String sessionId;
  final int generation;
  final int inputRevision;
  final String analysisSnapshotId;
  final String evaluationRequestJson;
  final String evaluationResponseJson;
  final PlanEvaluateResponseV1 parsedResponse;
}
