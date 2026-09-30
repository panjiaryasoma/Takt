import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:takt_mobile/calendar/ics_import.dart';
import 'package:takt_mobile/data/database/app_database.dart';
import 'package:takt_mobile/data/repositories/drift_schedule_repository.dart';
import 'package:takt_mobile/screens/ics_import_screen.dart';
import 'package:takt_mobile/screens/jadwal_ringkasan_screen.dart';
import 'package:takt_mobile/screens/tambah_jadwal_screen.dart';
import 'package:takt_mobile/theme/app_theme.dart';
import 'package:takt_mobile/viewmodels/jadwal_view_model.dart';

void main() {
  test('Android launcher and native splash use the canonical Takt logo', () {
    expect(File('assets/branding/logo.jpg').existsSync(), isTrue);
    expect(File('assets/breanding/logo.png').existsSync(), isFalse);

    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final splash =
        File('android/app/src/main/res/drawable/launch_background.xml')
            .readAsStringSync();
    final android12 =
        File('android/app/src/main/res/values-v31/styles.xml')
            .readAsStringSync();

    expect(manifest, contains('android:icon="@drawable/takt_logo"'));
    expect(splash, contains('@drawable/takt_logo'));
    expect(splash, contains('@color/takt_bg'));
    expect(android12, contains('android:windowSplashScreenAnimatedIcon'));
    expect(android12, contains('@drawable/takt_logo'));
  });

  test('Google-style ICS parses timed events and fails closed on all-day data', () {
    final result = IcsCalendarParser().parse(
      'BEGIN:VCALENDAR\r\n'
      'VERSION:2.0\r\n'
      'BEGIN:VEVENT\r\n'
      'UID:timed-1@example\r\n'
      r'SUMMARY:Class\, WSN' '\r\n'
      'DTSTART;TZID=Asia/Jakarta:20260930T130000\r\n'
      'DTEND;TZID=Asia/Jakarta:20260930T150000\r\n'
      'END:VEVENT\r\n'
      'BEGIN:VEVENT\r\n'
      'UID:all-day-1@example\r\n'
      'SUMMARY:Birthday\r\n'
      'DTSTART;VALUE=DATE:20261001\r\n'
      'DTEND;VALUE=DATE:20261002\r\n'
      'END:VEVENT\r\n'
      'END:VCALENDAR\r\n',
    );

    expect(result.events, hasLength(2));
    expect(result.events.first.title, 'Class, WSN');
    expect(result.events.first.supported, isTrue);
    expect(result.events.first.timezone, 'Asia/Jakarta');
    expect(result.events.last.supported, isFalse);
    expect(
      result.events.last.unsupportedReason,
      contains('All-day events'),
    );
  });

  test('weekly ICS recurrence is normalized for the schedule engine', () {
    final event = IcsCalendarParser().parse(
      'BEGIN:VCALENDAR\n'
      'BEGIN:VEVENT\n'
      'UID:weekly-1@example\n'
      'SUMMARY:Research class\n'
      'DTSTART;TZID=Asia/Jakarta:20260928T090000\n'
      'DTEND;TZID=Asia/Jakarta:20260928T103000\n'
      'RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=WE,MO\n'
      'END:VEVENT\n'
      'END:VCALENDAR\n',
    ).events.single;

    expect(event.supported, isTrue);
    expect(event.rrule, 'FREQ=WEEKLY;BYDAY=MO,WE');
  });

  test('calendar import is deterministic and skips a second identical import',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = DriftScheduleRepository(database);
    final viewModel = JadwalViewModel(repository);
    addTearDown(viewModel.dispose);

    await viewModel.initialize();
    await Future<void>.delayed(Duration.zero);

    final event = IcsCalendarParser().parse(
      'BEGIN:VCALENDAR\n'
      'BEGIN:VEVENT\n'
      'UID:dedupe-1@example\n'
      'SUMMARY:Imported class\n'
      'DTSTART:20260930T090000Z\n'
      'DTEND:20260930T100000Z\n'
      'END:VEVENT\n'
      'END:VCALENDAR\n',
    ).events.single;

    final first = await viewModel.importIcsEvents([event]);
    await Future<void>.delayed(Duration.zero);
    final second = await viewModel.importIcsEvents([event]);

    expect(first.success, isTrue);
    expect(first.imported, 1);
    expect(second.success, isTrue);
    expect(second.imported, 0);
    expect(second.skippedDuplicates, 1);
    expect(viewModel.all, hasLength(1));
    expect(viewModel.all.single.source, 'ics');
  });

  testWidgets('ICS picker previews events before any schedule write',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = DriftScheduleRepository(database);
    final viewModel = JadwalViewModel(repository);
    addTearDown(viewModel.dispose);
    await viewModel.initialize();
    await Future<void>.delayed(Duration.zero);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: IcsImportScreen(
            pickText: () async => (
              name: 'calendar.ics',
              content: 'BEGIN:VCALENDAR\n'
                  'BEGIN:VEVENT\n'
                  'UID:preview-1@example\n'
                  'SUMMARY:Preview only\n'
                  'DTSTART:20260930T090000Z\n'
                  'DTEND:20260930T100000Z\n'
                  'END:VEVENT\n'
                  'END:VCALENDAR\n',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('choose-ics-file')));
    await tester.pumpAndSettle();

    expect(find.text('Preview only'), findsOneWidget);
    expect(viewModel.all, isEmpty);
    expect(
      tester.widget<FilledButton>(
        find.byKey(const Key('import-selected-ics')),
      ).onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('select-supported-ics')));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(
        find.byKey(const Key('import-selected-ics')),
      ).onPressed,
      isNotNull,
    );
    expect(viewModel.all, isEmpty);
  });

  testWidgets('the entire From and To cards open the native time picker',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = DriftScheduleRepository(database);
    final viewModel = JadwalViewModel(repository);
    addTearDown(viewModel.dispose);
    await viewModel.initialize();
    await Future<void>.delayed(Duration.zero);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: TambahJadwalScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final from = find.byKey(const Key('from-time-card'));
    await tester.ensureVisible(from);
    await tester.tapAt(tester.getTopLeft(from) + const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final to = find.byKey(const Key('to-time-card'));
    await tester.ensureVisible(to);
    await tester.tapAt(tester.getBottomRight(to) - const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
  });

  testWidgets('weekly summary highlights device-local today only in current week',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = DriftScheduleRepository(database);
    final viewModel = JadwalViewModel(repository);
    addTearDown(viewModel.dispose);
    await viewModel.initialize();
    await Future<void>.delayed(Duration.zero);
    viewModel.selectDate(DateTime(2026, 9, 30));

    Widget app(DateTime now) => ChangeNotifierProvider.value(
          value: viewModel,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: JadwalRingkasanScreen(
                onSwitchTab: (_) {},
                now: now,
              ),
            ),
          ),
        );

    await tester.pumpWidget(app(DateTime(2026, 9, 30, 10)));
    await tester.pump();

    Text day(String value) =>
        tester.widget<Text>(find.byKey(Key('weekly-day-$value')));
    expect(day('Wed').style?.color, C.accent);
    expect(day('Sat').style?.color, C.white);

    await tester.pumpWidget(app(DateTime(2026, 10, 7, 10)));
    await tester.pump();
    for (final label in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
      expect(day(label).style?.color, C.white);
    }
  });
}
