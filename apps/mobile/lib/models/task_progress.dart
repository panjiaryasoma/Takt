/// Model TASK_PROGRESS — progres pengerjaan satu SavedPlanTask (PK = taskId).
/// Catatan: actualMinutes NULL != 0 (belum dikerjakan berbeda dari 0 menit).
class TaskProgress {
  TaskProgress({
    required this.savedPlanTaskId,
    required this.progressPercent,
    this.actualMinutes,
    required this.updatedAtEpochMs,
  });

  final String savedPlanTaskId;

  /// 0..100.
  final int progressPercent;

  /// null = belum ada catatan waktu; 0 = tercatat 0 menit. Keduanya beda makna.
  final int? actualMinutes;

  final int updatedAtEpochMs;

  DateTime get updatedAt =>
      DateTime.fromMillisecondsSinceEpoch(updatedAtEpochMs);

  factory TaskProgress.fromMap(Map<String, Object?> m) => TaskProgress(
        savedPlanTaskId: m['saved_plan_task_id']! as String,
        progressPercent: m['progress_percent']! as int,
        actualMinutes: m['actual_minutes'] as int?,
        updatedAtEpochMs: m['updated_at_epoch_ms']! as int,
      );

  Map<String, Object?> toMap() => {
        'saved_plan_task_id': savedPlanTaskId,
        'progress_percent': progressPercent,
        'actual_minutes': actualMinutes,
        'updated_at_epoch_ms': updatedAtEpochMs,
      };

  TaskProgress copyWith({
    int? progressPercent,
    int? actualMinutes,
    bool clearActualMinutes = false,
    int? updatedAtEpochMs,
  }) =>
      TaskProgress(
        savedPlanTaskId: savedPlanTaskId,
        progressPercent: progressPercent ?? this.progressPercent,
        actualMinutes:
            clearActualMinutes ? null : (actualMinutes ?? this.actualMinutes),
        updatedAtEpochMs: updatedAtEpochMs ?? this.updatedAtEpochMs,
      );
}
