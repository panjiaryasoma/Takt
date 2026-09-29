import '../../models/accepted_commitment.dart';
import '../../models/active_accepted_block.dart';
import '../../models/enums.dart';
import '../../models/saved_plan.dart';
import '../../models/saved_plan_revision.dart';
import '../../models/saved_plan_task.dart';
import '../../models/task_progress.dart';

final class SavedPlanSummary {
  const SavedPlanSummary({
    required this.plan,
    required this.currentRevision,
    required this.title,
    required this.deadline,
    required this.stale,
  });

  final SavedPlan plan;
  final SavedPlanRevision currentRevision;
  final String title;
  final DateTime deadline;
  final bool stale;
}

final class SavedPlanTaskState {
  const SavedPlanTaskState({
    required this.task,
    required this.progress,
  });

  final SavedPlanTask task;
  final TaskProgress progress;
}

final class SavedPlanDetail {
  const SavedPlanDetail({
    required this.summary,
    required this.revisions,
    required this.tasks,
    required this.acceptedCommitments,
  });

  final SavedPlanSummary summary;
  final List<SavedPlanRevision> revisions;
  final List<SavedPlanTaskState> tasks;
  final List<AcceptedCommitment> acceptedCommitments;
}

abstract class SavedPlanRepository {
  Future<void> initialize();

  Stream<List<SavedPlanSummary>> watchSummaries();

  Future<List<SavedPlanSummary>> listSummaries();

  Future<SavedPlan?> planForCompetition(String competitionId);

  Future<SavedPlanRevision> acceptEvaluation({
    required String evaluationId,
    required String candidateId,
    required SelectionSource selectionSource,
  });

  Future<List<ActiveAcceptedBlock>> activeAcceptedBlocks({
    String? excludingSavedPlanId,
  });

  Future<SavedPlanDetail?> loadDetail(String savedPlanId);

  Future<void> updateTaskProgress({
    required String savedPlanTaskId,
    required int progressPercent,
    int? actualMinutes,
    bool clearActualMinutes = false,
  });

  Future<void> refresh();

  Future<void> close();
}
