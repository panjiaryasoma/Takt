import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

final class IcsImportEvent {
  const IcsImportEvent({
    required this.uid,
    required this.title,
    required this.startAtEpochMs,
    required this.endAtEpochMs,
    required this.timezone,
    required this.supported,
    this.description,
    this.location,
    this.rrule,
    this.activeUntilEpochMs,
    this.unsupportedReason,
  });

  final String uid;
  final String title;
  final String? description;
  final String? location;
  final int startAtEpochMs;
  final int endAtEpochMs;
  final String timezone;
  final String? rrule;
  final int? activeUntilEpochMs;
  final bool supported;
  final String? unsupportedReason;

  bool get isRecurring => rrule != null;

  String get commitmentId {
    final material = '$uid|$startAtEpochMs|$endAtEpochMs|${rrule ?? ''}';
    final digest = sha256.convert(utf8.encode(material)).toString();
    return 'ics_${digest.substring(0, 24)}';
  }
}

final class IcsParseResult {
  const IcsParseResult({
    required this.events,
    required this.skippedCancelled,
  });

  final List<IcsImportEvent> events;
  final int skippedCancelled;
}

final class IcsCalendarParser {
  IcsCalendarParser({this.defaultTimezone = 'Asia/Jakarta'}) {
    _ensureTimezones();
  }

  final String defaultTimezone;
  static bool _timezonesReady = false;

  static void _ensureTimezones() {
    if (_timezonesReady) return;
    tz_data.initializeTimeZones();
    _timezonesReady = true;
  }

  IcsParseResult parse(String source) {
    final lines = _unfold(source);
    final events = <IcsImportEvent>[];
    var skippedCancelled = 0;
    List<_IcsProperty>? block;

    for (final line in lines) {
      if (line == 'BEGIN:VEVENT') {
        if (block != null) {
          throw const FormatException('Nested VEVENT is not supported.');
        }
        block = <_IcsProperty>[];
        continue;
      }
      if (line == 'END:VEVENT') {
        final current = block;
        if (current == null) {
          throw const FormatException('END:VEVENT without BEGIN:VEVENT.');
        }
        block = null;
        if (_value(current, 'STATUS')?.toUpperCase() == 'CANCELLED') {
          skippedCancelled++;
          continue;
        }
        events.add(_parseEvent(current));
        continue;
      }
      if (block != null && line.isNotEmpty) {
        block.add(_IcsProperty.parse(line));
      }
    }

    if (block != null) {
      throw const FormatException('Unclosed VEVENT.');
    }
    if (events.isEmpty && skippedCancelled == 0) {
      throw const FormatException('No VEVENT entries were found.');
    }

    return IcsParseResult(
      events: List<IcsImportEvent>.unmodifiable(events),
      skippedCancelled: skippedCancelled,
    );
  }

  IcsImportEvent _parseEvent(List<_IcsProperty> properties) {
    final uid = _requiredValue(properties, 'UID');
    final rawTitle = _value(properties, 'SUMMARY') ?? '(Untitled event)';
    final title = _decodeText(rawTitle).trim();
    final description = _optionalDecoded(properties, 'DESCRIPTION');
    final location = _optionalDecoded(properties, 'LOCATION');
    final startProperty = _requiredProperty(properties, 'DTSTART');
    final endProperty = _requiredProperty(properties, 'DTEND');

    String? unsupported;
    final hasExceptionShape = _has(properties, 'EXDATE') ||
        _has(properties, 'RDATE') ||
        _has(properties, 'RECURRENCE-ID');
    if (hasExceptionShape) {
      unsupported =
          'Recurring exceptions are not supported by this importer yet.';
    }

    final start = _parseDate(startProperty);
    final end = _parseDate(endProperty);
    if (start.allDay || end.allDay) {
      unsupported ??= 'All-day events are not imported as work capacity.';
    }
    if (end.instant.millisecondsSinceEpoch <=
        start.instant.millisecondsSinceEpoch) {
      unsupported ??= 'Event end time must be after its start time.';
    }

    final recurrence = _parseRecurrence(
      _value(properties, 'RRULE'),
      eventTimezone: start.timezone,
    );
    unsupported ??= recurrence.unsupportedReason;

    return IcsImportEvent(
      uid: uid,
      title: title.isEmpty ? '(Untitled event)' : title,
      description: description,
      location: location,
      startAtEpochMs: _floorToMinute(start.instant.millisecondsSinceEpoch),
      endAtEpochMs: _floorToMinute(end.instant.millisecondsSinceEpoch),
      timezone: start.timezone,
      rrule: recurrence.rrule,
      activeUntilEpochMs: recurrence.activeUntilEpochMs,
      supported: unsupported == null,
      unsupportedReason: unsupported,
    );
  }

  _ParsedDate _parseDate(_IcsProperty property) {
    final raw = property.value.trim();
    final allDay =
        property.params['VALUE']?.toUpperCase() == 'DATE' || !raw.contains('T');
    if (allDay) {
      final day = _parseParts(raw, requireTime: false);
      final instant = DateTime(day.year, day.month, day.day);
      return _ParsedDate(
        instant: instant,
        timezone: property.params['TZID'] ?? defaultTimezone,
        allDay: true,
      );
    }

    final parts = _parseParts(raw, requireTime: true);
    if (raw.endsWith('Z')) {
      return _ParsedDate(
        instant: DateTime.utc(
          parts.year,
          parts.month,
          parts.day,
          parts.hour,
          parts.minute,
          parts.second,
        ),
        timezone: 'UTC',
        allDay: false,
      );
    }

    final timezone = property.params['TZID'] ?? defaultTimezone;
    try {
      final location = tz.getLocation(timezone);
      return _ParsedDate(
        instant: tz.TZDateTime(
          location,
          parts.year,
          parts.month,
          parts.day,
          parts.hour,
          parts.minute,
          parts.second,
        ),
        timezone: timezone,
        allDay: false,
      );
    } on Object {
      throw FormatException('Unsupported TZID "$timezone".');
    }
  }

  _Recurrence _parseRecurrence(
    String? raw, {
    required String eventTimezone,
  }) {
    if (raw == null || raw.trim().isEmpty) {
      return const _Recurrence();
    }

    final parts = <String, String>{};
    for (final fragment in raw.split(';')) {
      final separator = fragment.indexOf('=');
      if (separator <= 0 || separator == fragment.length - 1) {
        return const _Recurrence(
          unsupportedReason: 'Malformed RRULE.',
        );
      }
      parts[fragment.substring(0, separator).toUpperCase()] =
          fragment.substring(separator + 1);
    }

    if (parts['FREQ']?.toUpperCase() != 'WEEKLY') {
      return const _Recurrence(
        unsupportedReason:
            'Only weekly recurring events can be imported automatically.',
      );
    }
    final interval = int.tryParse(parts['INTERVAL'] ?? '1');
    if (interval != 1) {
      return const _Recurrence(
        unsupportedReason:
            'Recurring intervals other than every week are not supported.',
      );
    }
    if (parts.containsKey('COUNT')) {
      return const _Recurrence(
        unsupportedReason: 'COUNT-based recurrence is not supported yet.',
      );
    }

    final byDay = (parts['BYDAY'] ?? '')
        .split(',')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    const allowedDays = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
    if (byDay.isEmpty || byDay.any((value) => !allowedDays.contains(value))) {
      return const _Recurrence(
        unsupportedReason: 'Weekly recurrence requires plain BYDAY values.',
      );
    }

    int? activeUntilEpochMs;
    final until = parts['UNTIL'];
    if (until != null) {
      try {
        final property = _IcsProperty(
          name: 'UNTIL',
          params: until.endsWith('Z') ? const {} : {'TZID': eventTimezone},
          value: until,
        );
        final parsed = _parseDate(property);
        if (parsed.allDay) {
          return const _Recurrence(
            unsupportedReason:
                'Date-only recurrence end values are not supported yet.',
          );
        }
        activeUntilEpochMs =
            _floorToMinute(parsed.instant.millisecondsSinceEpoch) + 60000;
      } on FormatException {
        return const _Recurrence(
          unsupportedReason: 'RRULE UNTIL could not be parsed safely.',
        );
      }
    }

    final sortedDays = [...byDay]
      ..sort((a, b) => allowedDays.indexOf(a).compareTo(allowedDays.indexOf(b)));
    return _Recurrence(
      rrule: 'FREQ=WEEKLY;BYDAY=${sortedDays.join(',')}',
      activeUntilEpochMs: activeUntilEpochMs,
    );
  }

  static List<String> _unfold(String source) {
    final normalized =
        source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rawLines = normalized.split('\n');
    final lines = <String>[];
    for (final line in rawLines) {
      if ((line.startsWith(' ') || line.startsWith('\t')) && lines.isNotEmpty) {
        lines[lines.length - 1] += line.substring(1);
      } else {
        lines.add(line.trimRight());
      }
    }
    return lines;
  }

  static _DateParts _parseParts(String raw, {required bool requireTime}) {
    final value = raw.endsWith('Z') ? raw.substring(0, raw.length - 1) : raw;
    final match = RegExp(
      requireTime
          ? r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?$'
          : r'^(\d{4})(\d{2})(\d{2})$',
    ).firstMatch(value);
    if (match == null) {
      throw FormatException('Unsupported iCalendar date "$raw".');
    }
    return _DateParts(
      year: int.parse(match.group(1)!),
      month: int.parse(match.group(2)!),
      day: int.parse(match.group(3)!),
      hour: requireTime ? int.parse(match.group(4)!) : 0,
      minute: requireTime ? int.parse(match.group(5)!) : 0,
      second: requireTime && match.group(6) != null
          ? int.parse(match.group(6)!)
          : 0,
    );
  }

  static bool _has(List<_IcsProperty> properties, String name) =>
      properties.any((property) => property.name == name);

  static _IcsProperty _requiredProperty(
    List<_IcsProperty> properties,
    String name,
  ) {
    for (final property in properties) {
      if (property.name == name) return property;
    }
    throw FormatException('VEVENT is missing $name.');
  }

  static String _requiredValue(
    List<_IcsProperty> properties,
    String name,
  ) {
    final value = _value(properties, name);
    if (value == null || value.trim().isEmpty) {
      throw FormatException('VEVENT is missing $name.');
    }
    return value.trim();
  }

  static String? _value(List<_IcsProperty> properties, String name) {
    for (final property in properties) {
      if (property.name == name) return property.value;
    }
    return null;
  }

  static String? _optionalDecoded(
    List<_IcsProperty> properties,
    String name,
  ) {
    final value = _value(properties, name);
    if (value == null || value.isEmpty) return null;
    final decoded = _decodeText(value).trim();
    return decoded.isEmpty ? null : decoded;
  }

  static String _decodeText(String value) => value
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\N', '\n')
      .replaceAll(r'\,', ',')
      .replaceAll(r'\;', ';')
      .replaceAll('\\\\', '\\');

  static int _floorToMinute(int epochMs) => (epochMs ~/ 60000) * 60000;
}

final class _IcsProperty {
  const _IcsProperty({
    required this.name,
    required this.params,
    required this.value,
  });

  factory _IcsProperty.parse(String line) {
    final separator = line.indexOf(':');
    if (separator <= 0) {
      throw FormatException('Malformed iCalendar property "$line".');
    }
    final header = line.substring(0, separator);
    final value = line.substring(separator + 1);
    final parts = header.split(';');
    final params = <String, String>{};
    for (final rawParam in parts.skip(1)) {
      final equals = rawParam.indexOf('=');
      if (equals <= 0 || equals == rawParam.length - 1) continue;
      params[rawParam.substring(0, equals).toUpperCase()] =
          rawParam.substring(equals + 1).replaceAll('"', '');
    }
    return _IcsProperty(
      name: parts.first.toUpperCase(),
      params: Map<String, String>.unmodifiable(params),
      value: value,
    );
  }

  final String name;
  final Map<String, String> params;
  final String value;
}

final class _ParsedDate {
  const _ParsedDate({
    required this.instant,
    required this.timezone,
    required this.allDay,
  });

  final DateTime instant;
  final String timezone;
  final bool allDay;
}

final class _DateParts {
  const _DateParts({
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    required this.second,
  });

  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;
  final int second;
}

final class _Recurrence {
  const _Recurrence({
    this.rrule,
    this.activeUntilEpochMs,
    this.unsupportedReason,
  });

  final String? rrule;
  final int? activeUntilEpochMs;
  final String? unsupportedReason;
}
