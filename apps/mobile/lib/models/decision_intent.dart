import 'enums.dart';
import 'evaluation_session.dart';

/// Completion of this callback means the host handled the handoff, not that
/// this component may claim persistence. 4B revalidates before writing.
typedef AcceptCandidateHandler = Future<void> Function(
  EvaluationSession session,
  AcceptCandidateIntent intent,
);

final class AcceptCandidateIntent {
  const AcceptCandidateIntent({
    required this.sessionId,
    required this.evaluationId,
    required this.candidateId,
    required this.selectionSource,
  });
  final String sessionId;
  final String evaluationId;
  final String candidateId;
  final SelectionSource selectionSource;
}

final class EditConstraintsIntent {
  const EditConstraintsIntent({
    required this.sessionId,
    required this.evaluationId,
    required this.inputRevision,
  });
  final String sessionId;
  final String evaluationId;
  final int inputRevision;
}

final class IgnoreRecommendationIntent {
  const IgnoreRecommendationIntent({
    required this.sessionId,
    required this.evaluationId,
    required this.inputRevision,
  });
  final String sessionId;
  final String evaluationId;
  final int inputRevision;
}
