/// Model RECURRENCE_RULES — aturan pengulangan sebuah komitmen.
/// Satu commitment punya paling banyak satu rule (commitment_id UNIQUE).
class RecurrenceRule {
  RecurrenceRule({
    required this.id,
    required this.commitmentId,
    required this.rrule,
    required this.timezone,
    required this.activeFromEpochMs,
    this.activeUntilEpochMs,
  });

  final String id;
  final String commitmentId;

  /// String RRULE iCal, mis. "FREQ=WEEKLY;BYDAY=WE".
  final String rrule;
  final String timezone;
  final int activeFromEpochMs;

  /// null = berlaku selamanya.
  final int? activeUntilEpochMs;

  DateTime get activeFrom =>
      DateTime.fromMillisecondsSinceEpoch(activeFromEpochMs);
  DateTime? get activeUntil => activeUntilEpochMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(activeUntilEpochMs!);

  factory RecurrenceRule.fromMap(Map<String, Object?> m) => RecurrenceRule(
        id: m['id']! as String,
        commitmentId: m['commitment_id']! as String,
        rrule: m['rrule']! as String,
        timezone: m['timezone']! as String,
        activeFromEpochMs: m['active_from_epoch_ms']! as int,
        activeUntilEpochMs: m['active_until_epoch_ms'] as int?,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'commitment_id': commitmentId,
        'rrule': rrule,
        'timezone': timezone,
        'active_from_epoch_ms': activeFromEpochMs,
        'active_until_epoch_ms': activeUntilEpochMs,
      };

  RecurrenceRule copyWith({
    String? id,
    String? commitmentId,
    String? rrule,
    String? timezone,
    int? activeFromEpochMs,
    int? activeUntilEpochMs,
  }) =>
      RecurrenceRule(
        id: id ?? this.id,
        commitmentId: commitmentId ?? this.commitmentId,
        rrule: rrule ?? this.rrule,
        timezone: timezone ?? this.timezone,
        activeFromEpochMs: activeFromEpochMs ?? this.activeFromEpochMs,
        activeUntilEpochMs: activeUntilEpochMs ?? this.activeUntilEpochMs,
      );
}
