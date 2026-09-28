import 'commitment.dart';

/// One concrete calendar occurrence derived from a commitment.
///
/// For one-off commitments, [recurrenceRuleId] is null. For recurring
/// commitments, [originalStartAtEpochMs] identifies the occurrence targeted by
/// a recurrence exception even when the rendered occurrence has been moved.
class ScheduleOccurrence {
  const ScheduleOccurrence({
    required this.commitment,
    required this.startAtEpochMs,
    required this.endAtEpochMs,
    required this.originalStartAtEpochMs,
    this.recurrenceRuleId,
  });

  final Commitment commitment;
  final int startAtEpochMs;
  final int endAtEpochMs;
  final int originalStartAtEpochMs;
  final String? recurrenceRuleId;

  bool get isRecurring => recurrenceRuleId != null;

  DateTime get startAt => DateTime.fromMillisecondsSinceEpoch(startAtEpochMs);
  DateTime get endAt => DateTime.fromMillisecondsSinceEpoch(endAtEpochMs);

  int get durationMinutes => (endAtEpochMs - startAtEpochMs) ~/ 60000;
}
