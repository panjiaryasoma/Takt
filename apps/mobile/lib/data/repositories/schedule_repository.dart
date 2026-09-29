import '../../models/commitment.dart';
import '../../models/planning_preferences.dart';
import '../../models/recurrence_exception.dart';
import '../../models/recurrence_rule.dart';

class ScheduleState {
  const ScheduleState({
    required this.commitments,
    required this.recurrenceRules,
    required this.recurrenceExceptions,
    required this.preferences,
  });

  factory ScheduleState.empty() => ScheduleState(
        commitments: const [],
        recurrenceRules: const [],
        recurrenceExceptions: const [],
        preferences: PlanningPreferences.defaults(),
      );

  final List<Commitment> commitments;
  final List<RecurrenceRule> recurrenceRules;
  final List<RecurrenceException> recurrenceExceptions;
  final PlanningPreferences preferences;
}

abstract class ScheduleRepository {
  Future<void> initialize();

  Stream<ScheduleState> watchState();

  Future<ScheduleState> loadState();

  Future<void> refresh();

  Future<void> createCommitment(
    Commitment commitment, {
    RecurrenceRule? recurrenceRule,
  });

  Future<void> updateCommitment(
    Commitment commitment, {
    RecurrenceRule? recurrenceRule,
  });

  Future<void> deleteCommitment(String commitmentId);

  Future<void> upsertRecurrenceException(RecurrenceException exception);

  Future<void> savePlanningPreferences(PlanningPreferences preferences);

  Future<void> close();
}
