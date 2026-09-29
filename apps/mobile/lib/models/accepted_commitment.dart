/// Model ACCEPTED_COMMITMENTS — blok waktu yang sudah diterima user dari
/// sebuah task rencana (hasil "accept" rekomendasi menjadi komitmen nyata).
/// Invarian: end - start == allocatedMinutes * 60000.
class AcceptedCommitment {
  AcceptedCommitment({
    required this.id,
    required this.savedPlanRevisionId,
    required this.savedPlanTaskId,
    required this.sourceBlockOrdinal,
    required this.startAtEpochMs,
    required this.endAtEpochMs,
    required this.allocatedMinutes,
    required this.originalAvailabilitySource,
    required this.sourceBlockJson,
    required this.acceptedAtEpochMs,
  });

  final String id;
  final String savedPlanRevisionId;
  final String savedPlanTaskId;
  final int sourceBlockOrdinal;
  final int startAtEpochMs;
  final int endAtEpochMs;
  final int allocatedMinutes;
  final String originalAvailabilitySource;
  final String sourceBlockJson;
  final int acceptedAtEpochMs;

  DateTime get startAt => DateTime.fromMillisecondsSinceEpoch(startAtEpochMs);
  DateTime get endAt => DateTime.fromMillisecondsSinceEpoch(endAtEpochMs);

  factory AcceptedCommitment.fromMap(Map<String, Object?> m) =>
      AcceptedCommitment(
        id: m['id']! as String,
        savedPlanRevisionId: m['saved_plan_revision_id']! as String,
        savedPlanTaskId: m['saved_plan_task_id']! as String,
        sourceBlockOrdinal: m['source_block_ordinal']! as int,
        startAtEpochMs: m['start_at_epoch_ms']! as int,
        endAtEpochMs: m['end_at_epoch_ms']! as int,
        allocatedMinutes: m['allocated_minutes']! as int,
        originalAvailabilitySource:
            m['original_availability_source']! as String,
        sourceBlockJson: m['source_block_json']! as String,
        acceptedAtEpochMs: m['accepted_at_epoch_ms']! as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'saved_plan_revision_id': savedPlanRevisionId,
        'saved_plan_task_id': savedPlanTaskId,
        'source_block_ordinal': sourceBlockOrdinal,
        'start_at_epoch_ms': startAtEpochMs,
        'end_at_epoch_ms': endAtEpochMs,
        'allocated_minutes': allocatedMinutes,
        'original_availability_source': originalAvailabilitySource,
        'source_block_json': sourceBlockJson,
        'accepted_at_epoch_ms': acceptedAtEpochMs,
      };
}
