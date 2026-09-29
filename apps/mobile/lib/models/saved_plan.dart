/// Model SAVED_PLANS — rencana tersimpan untuk satu kompetisi (1:1).
class SavedPlan {
  SavedPlan({
    required this.id,
    required this.competitionId,
    required this.createdAtEpochMs,
    required this.updatedAtEpochMs,
  });

  final String id;
  final String competitionId;
  final int createdAtEpochMs;
  final int updatedAtEpochMs;

  DateTime get createdAt =>
      DateTime.fromMillisecondsSinceEpoch(createdAtEpochMs);

  factory SavedPlan.fromMap(Map<String, Object?> m) => SavedPlan(
        id: m['id']! as String,
        competitionId: m['competition_id']! as String,
        createdAtEpochMs: m['created_at_epoch_ms']! as int,
        updatedAtEpochMs: m['updated_at_epoch_ms']! as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'competition_id': competitionId,
        'created_at_epoch_ms': createdAtEpochMs,
        'updated_at_epoch_ms': updatedAtEpochMs,
      };
}
