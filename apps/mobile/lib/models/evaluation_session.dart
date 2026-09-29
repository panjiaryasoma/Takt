import 'plan_evaluation_wire.dart';

/// Host-owned snapshot. The 4B host must pair/validate request, response and
/// analysis snapshot before publication, and discard late request generations.
/// The component carries the original request unchanged; it never assembles it.
final class EvaluationSession {
  EvaluationSession._({
    required this.sessionId,
    required this.generation,
    required this.inputRevision,
    required this.analysisSnapshotId,
    required this.originalRequestJson,
    required this.originalResponseJson,
  }) : parsedResponse = PlanEvaluateResponseV1.parse(originalResponseJson);

  factory EvaluationSession.fromRaw({
    required String sessionId,
    required int generation,
    required int inputRevision,
    required String analysisSnapshotId,
    required String originalRequestJson,
    required String originalResponseJson,
  }) {
    if (sessionId.trim().isEmpty || analysisSnapshotId.trim().isEmpty ||
        originalRequestJson.trim().isEmpty || generation < 0 || inputRevision < 0) {
      throw const FormatException('Invalid evaluation session metadata');
    }
    return EvaluationSession._(
      sessionId: sessionId,
      generation: generation,
      inputRevision: inputRevision,
      analysisSnapshotId: analysisSnapshotId,
      originalRequestJson: originalRequestJson,
      originalResponseJson: originalResponseJson,
    );
  }

  final String sessionId;
  final int generation;
  final int inputRevision;
  final String analysisSnapshotId;
  final String originalRequestJson;
  final String originalResponseJson;
  final PlanEvaluateResponseV1 parsedResponse;
}
