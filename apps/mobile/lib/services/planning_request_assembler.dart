import 'dart:convert';

import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/repositories/schedule_repository.dart';
import '../models/active_accepted_block.dart';
import '../models/analysis_snapshot.dart';
import '../models/planning_input_draft.dart';
import '../models/recurrence_exception.dart';
import '../models/recurrence_rule.dart';
import '../utils/deterministic_json.dart';

final class PlanningInputException implements Exception {
  const PlanningInputException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => code + ': ' + message;
}

final class PlanningAssembly {
  const PlanningAssembly({
    required this.requestMap,
    required this.requestJson,
    required this.windowPolicyJson,
  });

  final Map<String, Object?> requestMap;
  final String requestJson;
  final String windowPolicyJson;
}

final class PlanningRequestAssembler {
  PlanningRequestAssembler({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  static bool _zonesReady = false;

  PlanningAssembly assemble({
    required AnalysisSnapshot analysisSnapshot,
    required PlanningDraft draft,
    required ScheduleState schedule,
    required List<ActiveAcceptedBlock> acceptedBlocks,
  }) {
    _ensureTimeZones();
    if (draft.tasks.isEmpty) {
      throw const PlanningInputException(
        'PLANNING_INPUT_INVALID',
        'At least one user-confirmed planning task is required.',
      );
    }
    if (analysisSnapshot.competitionId.trim().isEmpty) {
      throw const PlanningInputException(
        'PLANNING_INPUT_UNAVAILABLE',
        'The analysis snapshot has no competition identity.',
      );
    }

    final raw = _decodeObject(analysisSnapshot.responseJson, 'analysis response');
    final reportBundle = _object(raw['report_bundle'], 'report_bundle');
    final report = _object(reportBundle['report'], 'report_bundle.report');
    final reportCompetitionId = report['competition_id'];
    if (reportCompetitionId != analysisSnapshot.competitionId) {
      throw const PlanningInputException(
        'PLANNING_INPUT_UNAVAILABLE',
        'The persisted analysis identity is inconsistent.',
      );
    }

    final deadline = _submissionDeadline(report);
    final location = _location(draft.windowPolicy.timezone);
    final nowLocal = tz.TZDateTime.from(_now().toUtc(), location);
    final localDayStart = _localBoundary(
      location,
      nowLocal.year,
      nowLocal.month,
      nowLocal.day,
      0,
      field: 'planning horizon start',
    );
    final horizonEnd = tz.TZDateTime.from(deadline.toUtc(), location);
    final horizonStart = localDayStart.toUtc().isBefore(horizonEnd.toUtc())
        ? localDayStart
        : tz.TZDateTime.from(
            horizonEnd.toUtc().subtract(const Duration(minutes: 1)),
            location,
          );

    // An empty expansion is meaningful: the user-confirmed work policy may
    // genuinely provide no usable time before the deadline. Never replace it
    // with a hidden fallback window. Deadline truth itself remains server-owned.
    final windows = _expandWindows(
      draft.windowPolicy,
      horizonStart: horizonStart,
      horizonEnd: horizonEnd,
    );

    final rulesByCommitment = <String, RecurrenceRule>{
      for (final rule in schedule.recurrenceRules) rule.commitmentId: rule,
    };
    final exceptionsByRule = <String, List<RecurrenceException>>{};
    for (final exception in schedule.recurrenceExceptions) {
      exceptionsByRule.putIfAbsent(exception.recurrenceRuleId, () => []).add(exception);
    }

    final commitments = <Map<String, Object?>>[];
    for (final commitment in schedule.commitments) {
      final rule = rulesByCommitment[commitment.id];
      commitments.add({
        'commitment_id': commitment.id,
        'type': commitment.type.wire,
        'start_at': _zonedIso(commitment.startAtEpochMs, commitment.timezone),
        'end_at': _zonedIso(commitment.endAtEpochMs, commitment.timezone),
        'timezone': commitment.timezone,
        'recurrence': rule == null
            ? null
            : {
                'rrule': rule.rrule,
                'timezone': rule.timezone,
                'active_from':
                    _zonedIso(rule.activeFromEpochMs, rule.timezone),
                'active_until': rule.activeUntilEpochMs == null
                    ? null
                    : _zonedIso(rule.activeUntilEpochMs!, rule.timezone),
              },
        'exceptions': rule == null
            ? const <Object?>[]
            : [
                for (final item in exceptionsByRule[rule.id] ?? const <RecurrenceException>[])
                  {
                    'original_start_at':
                        _zonedIso(item.originalStartAtEpochMs, rule.timezone),
                    'action': item.action.wire,
                    'replacement_start_at': item.replacementStartAtEpochMs == null
                        ? null
                        : _zonedIso(item.replacementStartAtEpochMs!, rule.timezone),
                    'replacement_end_at': item.replacementEndAtEpochMs == null
                        ? null
                        : _zonedIso(item.replacementEndAtEpochMs!, rule.timezone),
                  },
              ],
        'source': commitment.source,
      });
    }

    final request = <String, Object?>{
      'report_bundle': reportBundle,
      'readiness_context': draft.readinessContext.toWire(),
      'planning': {
        'workload': {
          'tasks': [for (final task in draft.tasks) task.toWire()],
          'assumptions': const <Object?>[],
        },
        'availability': {
          'horizon': {
            'start': _isoAware(horizonStart),
            'end': _isoAware(horizonEnd),
          },
          'work_windows': windows,
          'commitments': commitments,
          'accepted_commitments': [
            for (final block in acceptedBlocks)
              {
                'accepted_commitment_id': block.acceptedCommitmentId,
                'start_at': _zonedIso(
                  block.startAtEpochMs,
                  draft.preferences.timezone,
                ),
                'end_at': _zonedIso(
                  block.endAtEpochMs,
                  draft.preferences.timezone,
                ),
                'source': block.source,
              },
          ],
          'preferences': {
            'timezone': draft.preferences.timezone,
            'max_project_minutes_per_day':
                draft.preferences.maxProjectMinutesPerDay,
            'preferred_focus_minutes': draft.preferences.preferredFocusMinutes,
            'buffer_target_minutes': draft.preferences.bufferTargetMinutes,
          },
        },
      },
    };

    return PlanningAssembly(
      requestMap: request,
      requestJson: deterministicJsonEncode(request),
      windowPolicyJson: deterministicJsonEncode(draft.windowPolicy.toJson()),
    );
  }

  static void _ensureTimeZones() {
    if (_zonesReady) return;
    tzdata.initializeTimeZones();
    _zonesReady = true;
  }

  static tz.Location _location(String name) {
    try {
      return tz.getLocation(name);
    } on Object {
      throw PlanningInputException(
        'PLANNING_INPUT_UNAVAILABLE',
        'Unknown IANA timezone: ' + name,
      );
    }
  }

  static Map<String, dynamic> _decodeObject(String raw, String field) {
    try {
      final value = jsonDecode(raw);
      return _object(value, field);
    } on FormatException {
      rethrow;
    } on Object {
      throw PlanningInputException(
        'PLANNING_INPUT_UNAVAILABLE',
        'Invalid persisted ' + field + '.',
      );
    }
  }

  static Map<String, dynamic> _object(Object? value, String field) {
    if (value is! Map) {
      throw PlanningInputException(
        'PLANNING_INPUT_UNAVAILABLE',
        field + ' must be an object.',
      );
    }
    return Map<String, dynamic>.from(value);
  }

  static DateTime _submissionDeadline(Map<String, dynamic> report) {
    final fields = _object(report['canonical_fields'], 'canonical_fields');
    final deadlineField =
        _object(fields['submission_deadline'], 'submission_deadline');
    final state = deadlineField['state'];
    if (state != 'VERIFIED' && state != 'SINGLE_SOURCE') {
      throw const PlanningInputException(
        'PLANNING_INPUT_UNAVAILABLE',
        'A usable canonical submission deadline is required for planning.',
      );
    }
    final value =
        deadlineField['normalized_value'] ?? deadlineField['value'];
    if (value is! String ||
        !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
      throw const PlanningInputException(
        'PLANNING_INPUT_UNAVAILABLE',
        'The canonical submission deadline must include a timezone.',
      );
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw const PlanningInputException(
        'PLANNING_INPUT_UNAVAILABLE',
        'The canonical submission deadline is invalid.',
      );
    }
    if (parsed.second != 0 ||
        parsed.millisecond != 0 ||
        parsed.microsecond != 0) {
      throw const PlanningInputException(
        'PLANNING_INPUT_UNAVAILABLE',
        'The canonical submission deadline is not minute-aligned.',
      );
    }
    return parsed;
  }

  static List<Map<String, Object?>> _expandWindows(
    PlanningWindowPolicyV1 policy, {
    required tz.TZDateTime horizonStart,
    required tz.TZDateTime horizonEnd,
  }) {
    final location = _location(policy.timezone);
    final result = <Map<String, Object?>>[];
    var date = DateTime.utc(
      horizonStart.year,
      horizonStart.month,
      horizonStart.day,
    );
    final last = DateTime.utc(horizonEnd.year, horizonEnd.month, horizonEnd.day);

    while (!date.isAfter(last)) {
      final start = _localBoundary(
        location,
        date.year,
        date.month,
        date.day,
        policy.startMinutesOfDay,
        field: 'work window start',
      );
      final end = _localBoundary(
        location,
        date.year,
        date.month,
        date.day,
        policy.endMinutesOfDay,
        field: 'work window end',
      );

      final clippedStart = start.toUtc().isBefore(horizonStart.toUtc())
          ? horizonStart
          : start;
      final clippedEnd = end.toUtc().isAfter(horizonEnd.toUtc())
          ? horizonEnd
          : end;
      if (clippedStart.toUtc().isBefore(clippedEnd.toUtc())) {
        result.add({
          'start': _isoAware(tz.TZDateTime.from(clippedStart.toUtc(), location)),
          'end': _isoAware(tz.TZDateTime.from(clippedEnd.toUtc(), location)),
        });
      }
      date = date.add(const Duration(days: 1));
    }
    return result;
  }

  static tz.TZDateTime _localBoundary(
    tz.Location location,
    int year,
    int month,
    int day,
    int minutesOfDay, {
    required String field,
  }) {
    var date = DateTime.utc(year, month, day);
    var minutes = minutesOfDay;
    if (minutes == 1440) {
      date = date.add(const Duration(days: 1));
      minutes = 0;
    }
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    final candidate =
        tz.TZDateTime(location, date.year, date.month, date.day, hour, minute);

    bool sameWallClock(tz.TZDateTime value) =>
        value.year == date.year &&
        value.month == date.month &&
        value.day == date.day &&
        value.hour == hour &&
        value.minute == minute;

    if (!sameWallClock(candidate)) {
      throw PlanningInputException(
        'PLANNING_INPUT_UNAVAILABLE',
        field + ' falls in a nonexistent DST local time.',
      );
    }

    final candidates = <int>{};
    final center = candidate.toUtc();
    for (var delta = -240; delta <= 240; delta++) {
      final instant = center.add(Duration(minutes: delta));
      final local = tz.TZDateTime.from(instant, location);
      if (sameWallClock(local)) {
        candidates.add(instant.millisecondsSinceEpoch);
      }
    }
    if (candidates.length != 1) {
      throw PlanningInputException(
        'PLANNING_INPUT_UNAVAILABLE',
        field + ' is ambiguous at a DST transition.',
      );
    }
    return tz.TZDateTime.from(
      DateTime.fromMillisecondsSinceEpoch(candidates.single, isUtc: true),
      location,
    );
  }

  static String _zonedIso(int epochMs, String timezone) {
    final location = _location(timezone);
    final instant = DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true);
    return _isoAware(tz.TZDateTime.from(instant, location));
  }

  static String _isoAware(DateTime value) {
    String two(int value) => value.toString().padLeft(2, '0');
    final offsetMinutes = value.timeZoneOffset.inMinutes;
    final sign = offsetMinutes < 0 ? '-' : '+';
    final abs = offsetMinutes.abs();
    final offset = sign + two(abs ~/ 60) + ':' + two(abs % 60);
    return value.year.toString().padLeft(4, '0') +
        '-' +
        two(value.month) +
        '-' +
        two(value.day) +
        'T' +
        two(value.hour) +
        ':' +
        two(value.minute) +
        ':00' +
        offset;
  }
}
