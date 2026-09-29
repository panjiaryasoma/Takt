import '../../models/analysis_snapshot.dart';
import '../../models/evaluation.dart';
import '../../models/reevaluation_transition.dart';
import '../../models/reevaluation_wire.dart';

final class ReevaluationPersistenceResult {
  const ReevaluationPersistenceResult({
    required this.transition,
    this.evaluation,
  });

  final ReevaluationTransition transition;
  final Evaluation? evaluation;
}

abstract class EvaluationRepository {
  Future<void> initialize();

  Future<Evaluation?> evaluationById(String evaluationId);

  Future<Evaluation> persistEvaluation({
    required AnalysisSnapshot analysisSnapshot,
    required String evaluationRequestJson,
    required String evaluationResponseJson,
    required String planningWindowPolicyJson,
  });

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
  });

  Future<bool> isStale(String evaluationId);

  Future<void> close();
}
