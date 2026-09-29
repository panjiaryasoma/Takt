final class ActiveAcceptedBlock {
  const ActiveAcceptedBlock({
    required this.savedPlanId,
    required this.savedPlanRevisionId,
    required this.acceptedCommitmentId,
    required this.competitionId,
    required this.taskName,
    required this.startAtEpochMs,
    required this.endAtEpochMs,
    required this.source,
  });

  final String savedPlanId;
  final String savedPlanRevisionId;
  final String acceptedCommitmentId;
  final String competitionId;
  final String taskName;
  final int startAtEpochMs;
  final int endAtEpochMs;
  final String source;

  DateTime get startAt =>
      DateTime.fromMillisecondsSinceEpoch(startAtEpochMs);
  DateTime get endAt => DateTime.fromMillisecondsSinceEpoch(endAtEpochMs);
  int get durationMinutes => (endAtEpochMs - startAtEpochMs) ~/ 60000;
}
