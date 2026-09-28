import 'enums.dart';

/// Model RECURRENCE_EXCEPTIONS — pengecualian pada satu kejadian recurrence.
/// action CANCELLED = kejadian dibatalkan; MOVED = dipindah ke waktu pengganti.
class RecurrenceException {
  RecurrenceException({
    required this.id,
    required this.recurrenceRuleId,
    required this.originalStartAtEpochMs,
    required this.action,
    this.replacementStartAtEpochMs,
    this.replacementEndAtEpochMs,
  });

  final String id;
  final String recurrenceRuleId;
  final int originalStartAtEpochMs;
  final ExceptionAction action;

  /// Wajib diisi bila action == moved; null bila cancelled.
  final int? replacementStartAtEpochMs;
  final int? replacementEndAtEpochMs;

  DateTime get originalStartAt =>
      DateTime.fromMillisecondsSinceEpoch(originalStartAtEpochMs);

  factory RecurrenceException.fromMap(Map<String, Object?> m) =>
      RecurrenceException(
        id: m['id']! as String,
        recurrenceRuleId: m['recurrence_rule_id']! as String,
        originalStartAtEpochMs: m['original_start_at_epoch_ms']! as int,
        action: ExceptionAction.fromWire(m['action']! as String),
        replacementStartAtEpochMs: m['replacement_start_at_epoch_ms'] as int?,
        replacementEndAtEpochMs: m['replacement_end_at_epoch_ms'] as int?,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'recurrence_rule_id': recurrenceRuleId,
        'original_start_at_epoch_ms': originalStartAtEpochMs,
        'action': action.wire,
        'replacement_start_at_epoch_ms': replacementStartAtEpochMs,
        'replacement_end_at_epoch_ms': replacementEndAtEpochMs,
      };

  RecurrenceException copyWith({
    String? id,
    String? recurrenceRuleId,
    int? originalStartAtEpochMs,
    ExceptionAction? action,
    int? replacementStartAtEpochMs,
    int? replacementEndAtEpochMs,
  }) =>
      RecurrenceException(
        id: id ?? this.id,
        recurrenceRuleId: recurrenceRuleId ?? this.recurrenceRuleId,
        originalStartAtEpochMs:
            originalStartAtEpochMs ?? this.originalStartAtEpochMs,
        action: action ?? this.action,
        replacementStartAtEpochMs:
            replacementStartAtEpochMs ?? this.replacementStartAtEpochMs,
        replacementEndAtEpochMs:
            replacementEndAtEpochMs ?? this.replacementEndAtEpochMs,
      );
}
