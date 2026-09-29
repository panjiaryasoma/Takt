/// Model PLANNING_PREFERENCES — preferensi penjadwalan (baris tunggal, id=1).
class PlanningPreferences {
  PlanningPreferences({
    this.id = 1,
    required this.timezone,
    required this.maxProjectMinutesPerDay,
    required this.preferredFocusMinutes,
    required this.bufferTargetMinutes,
    required this.updatedAtEpochMs,
  });

  final int id;
  final String timezone;

  /// Batas menit proyek per hari (0..1440).
  final int maxProjectMinutesPerDay;

  /// Durasi fokus ideal per sesi (> 0).
  final int preferredFocusMinutes;

  /// Target buffer menit (>= 0).
  final int bufferTargetMinutes;

  final int updatedAtEpochMs;

  /// Nilai default masuk akal saat DB masih kosong.
  factory PlanningPreferences.defaults() => PlanningPreferences(
        timezone: 'Asia/Jakarta',
        maxProjectMinutesPerDay: 240,
        preferredFocusMinutes: 90,
        bufferTargetMinutes: 30,
        updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      );

  factory PlanningPreferences.fromMap(Map<String, Object?> m) =>
      PlanningPreferences(
        id: m['id']! as int,
        timezone: m['timezone']! as String,
        maxProjectMinutesPerDay: m['max_project_minutes_per_day']! as int,
        preferredFocusMinutes: m['preferred_focus_minutes']! as int,
        bufferTargetMinutes: m['buffer_target_minutes']! as int,
        updatedAtEpochMs: m['updated_at_epoch_ms']! as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'timezone': timezone,
        'max_project_minutes_per_day': maxProjectMinutesPerDay,
        'preferred_focus_minutes': preferredFocusMinutes,
        'buffer_target_minutes': bufferTargetMinutes,
        'updated_at_epoch_ms': updatedAtEpochMs,
      };

  PlanningPreferences copyWith({
    String? timezone,
    int? maxProjectMinutesPerDay,
    int? preferredFocusMinutes,
    int? bufferTargetMinutes,
    int? updatedAtEpochMs,
  }) =>
      PlanningPreferences(
        id: id,
        timezone: timezone ?? this.timezone,
        maxProjectMinutesPerDay:
            maxProjectMinutesPerDay ?? this.maxProjectMinutesPerDay,
        preferredFocusMinutes:
            preferredFocusMinutes ?? this.preferredFocusMinutes,
        bufferTargetMinutes: bufferTargetMinutes ?? this.bufferTargetMinutes,
        updatedAtEpochMs: updatedAtEpochMs ?? this.updatedAtEpochMs,
      );
}
