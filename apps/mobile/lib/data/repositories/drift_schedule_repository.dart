import 'dart:async';

import 'package:drift/drift.dart';

import '../../models/commitment.dart';
import '../../models/planning_preferences.dart';
import '../../models/recurrence_exception.dart';
import '../../models/recurrence_rule.dart';
import '../database/app_database.dart';
import 'schedule_repository.dart';

class DriftScheduleRepository implements ScheduleRepository {
  DriftScheduleRepository(this._db);

  final AppDatabase _db;
  final StreamController<ScheduleState> _changes =
      StreamController<ScheduleState>.broadcast();

  ScheduleState? _current;
  bool _initialized = false;
  bool _closed = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _db.initialize();
    await _ensureDefaultPreferences();
    _initialized = true;
    await refresh();
  }

  @override
  Stream<ScheduleState> watchState() async* {
    if (!_initialized) {
      await initialize();
    }
    if (_current case final state?) {
      yield state;
    }
    yield* _changes.stream;
  }

  @override
  Future<ScheduleState> loadState() async {
    if (!_initialized) {
      await initialize();
    }

    final commitmentRows = await _db.customSelect(
      'SELECT * FROM commitments ORDER BY start_at_epoch_ms, id',
    ).get();
    final ruleRows = await _db.customSelect(
      'SELECT * FROM recurrence_rules ORDER BY active_from_epoch_ms, id',
    ).get();
    final exceptionRows = await _db.customSelect(
      '''
SELECT * FROM recurrence_exceptions
ORDER BY recurrence_rule_id, original_start_at_epoch_ms, id
''',
    ).get();
    final preferenceRow = await _db.customSelect(
      'SELECT * FROM planning_preferences WHERE id = 1',
    ).getSingle();

    return ScheduleState(
      commitments: commitmentRows
          .map((row) => Commitment.fromMap(row.data))
          .toList(growable: false),
      recurrenceRules: ruleRows
          .map((row) => RecurrenceRule.fromMap(row.data))
          .toList(growable: false),
      recurrenceExceptions: exceptionRows
          .map((row) => RecurrenceException.fromMap(row.data))
          .toList(growable: false),
      preferences: PlanningPreferences.fromMap(preferenceRow.data),
    );
  }

  @override
  Future<void> refresh() async {
    final next = await loadState();
    _current = next;
    if (!_changes.isClosed) {
      _changes.add(next);
    }
  }

  @override
  Future<void> createCommitment(
    Commitment commitment, {
    RecurrenceRule? recurrenceRule,
  }) async {
    await initialize();
    await _db.transaction(() async {
      await _insertCommitment(commitment);
      if (recurrenceRule != null) {
        await _insertRecurrenceRule(recurrenceRule);
      }
    });
    await refresh();
  }

  @override
  Future<void> updateCommitment(
    Commitment commitment, {
    RecurrenceRule? recurrenceRule,
  }) async {
    await initialize();
    await _db.transaction(() async {
      await _db.customStatement(
        '''
UPDATE commitments
SET title = ?, category = ?, type = ?, start_at_epoch_ms = ?,
    end_at_epoch_ms = ?, timezone = ?, source = ?, updated_at_epoch_ms = ?
WHERE id = ?
''',
        [
          commitment.title,
          commitment.category,
          commitment.type.wire,
          commitment.startAtEpochMs,
          commitment.endAtEpochMs,
          commitment.timezone,
          commitment.source,
          commitment.updatedAtEpochMs,
          commitment.id,
        ],
      );

      if (recurrenceRule == null) {
        await _db.customStatement(
          'DELETE FROM recurrence_rules WHERE commitment_id = ?',
          [commitment.id],
        );
      } else {
        final previousRows = await _db.customSelect(
          'SELECT * FROM recurrence_rules WHERE commitment_id = ?',
          variables: [Variable<String>(commitment.id)],
        ).get();
        if (previousRows.isNotEmpty) {
          final previous = RecurrenceRule.fromMap(previousRows.single.data);
          final recurrenceChanged =
              previous.rrule != recurrenceRule.rrule ||
                  previous.timezone != recurrenceRule.timezone ||
                  previous.activeFromEpochMs != recurrenceRule.activeFromEpochMs ||
                  previous.activeUntilEpochMs != recurrenceRule.activeUntilEpochMs;
          if (recurrenceChanged) {
            await _db.customStatement(
              'DELETE FROM recurrence_exceptions WHERE recurrence_rule_id = ?',
              [previous.id],
            );
          }
        }

        await _db.customStatement(
          '''
INSERT INTO recurrence_rules (
  id, commitment_id, rrule, timezone, active_from_epoch_ms,
  active_until_epoch_ms
) VALUES (?, ?, ?, ?, ?, ?)
ON CONFLICT(commitment_id) DO UPDATE SET
  rrule = excluded.rrule,
  timezone = excluded.timezone,
  active_from_epoch_ms = excluded.active_from_epoch_ms,
  active_until_epoch_ms = excluded.active_until_epoch_ms
''',
          [
            recurrenceRule.id,
            recurrenceRule.commitmentId,
            recurrenceRule.rrule,
            recurrenceRule.timezone,
            recurrenceRule.activeFromEpochMs,
            recurrenceRule.activeUntilEpochMs,
          ],
        );
      }
    });
    await refresh();
  }

  @override
  Future<void> deleteCommitment(String commitmentId) async {
    await initialize();
    await _db.customStatement(
      'DELETE FROM commitments WHERE id = ?',
      [commitmentId],
    );
    await refresh();
  }

  @override
  Future<void> upsertRecurrenceException(
    RecurrenceException exception,
  ) async {
    await initialize();
    await _db.customStatement(
      '''
INSERT INTO recurrence_exceptions (
  id, recurrence_rule_id, original_start_at_epoch_ms, action,
  replacement_start_at_epoch_ms, replacement_end_at_epoch_ms
) VALUES (?, ?, ?, ?, ?, ?)
ON CONFLICT(recurrence_rule_id, original_start_at_epoch_ms) DO UPDATE SET
  action = excluded.action,
  replacement_start_at_epoch_ms = excluded.replacement_start_at_epoch_ms,
  replacement_end_at_epoch_ms = excluded.replacement_end_at_epoch_ms
''',
      [
        exception.id,
        exception.recurrenceRuleId,
        exception.originalStartAtEpochMs,
        exception.action.wire,
        exception.replacementStartAtEpochMs,
        exception.replacementEndAtEpochMs,
      ],
    );
    await refresh();
  }

  @override
  Future<void> savePlanningPreferences(
    PlanningPreferences preferences,
  ) async {
    await initialize();
    await _db.customStatement(
      '''
INSERT INTO planning_preferences (
  id, timezone, max_project_minutes_per_day, preferred_focus_minutes,
  buffer_target_minutes, updated_at_epoch_ms
) VALUES (?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  timezone = excluded.timezone,
  max_project_minutes_per_day = excluded.max_project_minutes_per_day,
  preferred_focus_minutes = excluded.preferred_focus_minutes,
  buffer_target_minutes = excluded.buffer_target_minutes,
  updated_at_epoch_ms = excluded.updated_at_epoch_ms
''',
      [
        preferences.id,
        preferences.timezone,
        preferences.maxProjectMinutesPerDay,
        preferences.preferredFocusMinutes,
        preferences.bufferTargetMinutes,
        preferences.updatedAtEpochMs,
      ],
    );
    await refresh();
  }

  Future<void> _ensureDefaultPreferences() async {
    final defaults = PlanningPreferences.defaults();
    await _db.customStatement(
      '''
INSERT OR IGNORE INTO planning_preferences (
  id, timezone, max_project_minutes_per_day, preferred_focus_minutes,
  buffer_target_minutes, updated_at_epoch_ms
) VALUES (?, ?, ?, ?, ?, ?)
''',
      [
        defaults.id,
        defaults.timezone,
        defaults.maxProjectMinutesPerDay,
        defaults.preferredFocusMinutes,
        defaults.bufferTargetMinutes,
        defaults.updatedAtEpochMs,
      ],
    );
  }

  Future<void> _insertCommitment(Commitment commitment) {
    return _db.customStatement(
      '''
INSERT INTO commitments (
  id, title, category, type, start_at_epoch_ms, end_at_epoch_ms,
  timezone, source, created_at_epoch_ms, updated_at_epoch_ms
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
      [
        commitment.id,
        commitment.title,
        commitment.category,
        commitment.type.wire,
        commitment.startAtEpochMs,
        commitment.endAtEpochMs,
        commitment.timezone,
        commitment.source,
        commitment.createdAtEpochMs,
        commitment.updatedAtEpochMs,
      ],
    );
  }

  Future<void> _insertRecurrenceRule(RecurrenceRule rule) {
    return _db.customStatement(
      '''
INSERT INTO recurrence_rules (
  id, commitment_id, rrule, timezone, active_from_epoch_ms,
  active_until_epoch_ms
) VALUES (?, ?, ?, ?, ?, ?)
''',
      [
        rule.id,
        rule.commitmentId,
        rule.rrule,
        rule.timezone,
        rule.activeFromEpochMs,
        rule.activeUntilEpochMs,
      ],
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _changes.close();
    await _db.close();
  }
}
