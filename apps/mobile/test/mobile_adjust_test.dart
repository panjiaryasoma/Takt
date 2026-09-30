import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:takt_mobile/calendar/ics_import.dart';
import 'package:takt_mobile/data/database/app_database.dart';
import 'package:takt_mobile/data/repositories/drift_schedule_repository.dart';
import 'package:takt_mobile/main.dart';
import 'package:takt_mobile/screens/ics_import_screen.dart';
import 'package:takt_mobile/screens/jadwal_harian_screen.dart';
import 'package:takt_mobile/screens/jadwal_ringkasan_screen.dart';
import 'package:takt_mobile/screens/tambah_jadwal_screen.dart';
import 'package:takt_mobile/theme/app_theme.dart';
import 'package:takt_mobile/viewmodels/jadwal_view_model.dart';

Future<void> _pumpBounded(
  WidgetTester tester, {
  int frames = 12,
}) async {
  for (var index = 0; index < frames; index++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

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

    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(File('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.jpg').existsSync(), isTrue);
    expect(splash, contains('@drawable/takt_logo'));
    expect(splash, contains('@color/takt_bg'));
    expect(android12, contains('android:windowSplashScreenAnimatedIcon'));
    expect(android12, contains('@drawable/takt_logo'));
  });

  test('iOS launch and AppIcon generation use the canonical Takt logo', () {
    final launchScreen =
        File('ios/Runner/Base.lproj/LaunchScreen.storyboard')
            .readAsStringSync();
    final imageSet = File(
      'ios/Runner/Assets.xcassets/TaktLogo.imageset/Contents.json',
    ).readAsStringSync();
    final project =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final generator =
        File('ios/scripts/generate_takt_branding.sh').readAsStringSync();
    final ignore = File('ios/.gitignore').readAsStringSync();

    expect(
      File(
        'ios/Runner/Assets.xcassets/TaktLogo.imageset/takt_logo.jpg',
      ).existsSync(),
      isTrue,
    );
    expect(launchScreen, contains('image="TaktLogo"'));
    expect(launchScreen, contains('red="0.1764705882"'));
    expect(imageSet, contains('"filename" : "takt_logo.jpg"'));
    expect(project, contains('Generate Takt Branding'));
    expect(project, contains('PRODUCT_BUNDLE_IDENTIFIER = com.panjiaryasoma.takt;'));
    expect(project, isNot(contains('com.example.taktMobile')));
    expect(
      project,
      contains(
        'A37B3D9E2F614EBA95C14001 /* Generate Takt Branding */,',
      ),
    );
    expect(generator, contains('/usr/bin/sips'));
    expect(generator, contains('Icon-App-1024x1024@1x.png'));
    expect(
      ignore,
      contains('Runner/Assets.xcassets/AppIcon.appiconset/*.png'),
    );
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

  test('ICS parser rejects duplicate RRULE keys and duplicate BYDAY values', () {
    final parser = IcsCalendarParser();

    final duplicateKey = parser.parse(
      'BEGIN:VCALENDAR\n'
      'BEGIN:VEVENT\n'
      'UID:duplicate-key@example\n'
      'SUMMARY:Duplicate key\n'
      'DTSTART:20260928T090000Z\n'
      'DTEND:20260928T100000Z\n'
      'RRULE:FREQ=WEEKLY;FREQ=WEEKLY;BYDAY=MO\n'
      'END:VEVENT\n'
      'END:VCALENDAR\n',
    ).events.single;
    expect(duplicateKey.supported, isFalse);
    expect(duplicateKey.unsupportedReason, contains('Duplicate RRULE key'));

    final duplicateDay = parser.parse(
      'BEGIN:VCALENDAR\n'
      'BEGIN:VEVENT\n'
      'UID:duplicate-day@example\n'
      'SUMMARY:Duplicate weekday\n'
      'DTSTART:20260928T090000Z\n'
      'DTEND:20260928T100000Z\n'
      'RRULE:FREQ=WEEKLY;BYDAY=MO,MO\n'
      'END:VEVENT\n'
      'END:VCALENDAR\n',
    ).events.single;
    expect(duplicateDay.supported, isFalse);
    expect(duplicateDay.unsupportedReason, contains('must not contain duplicates'));
  });

  test('ICS parser rejects unsupported week starts and invalid dates', () {
    final parser = IcsCalendarParser();

    final sundayWeekStart = parser.parse(
      'BEGIN:VCALENDAR\n'
      'BEGIN:VEVENT\n'
      'UID:wkst@example\n'
      'SUMMARY:Different week start\n'
      'DTSTART:20260928T090000Z\n'
      'DTEND:20260928T100000Z\n'
      'RRULE:FREQ=WEEKLY;WKST=SU;BYDAY=MO\n'
      'END:VEVENT\n'
      'END:VCALENDAR\n',
    ).events.single;
    expect(sundayWeekStart.supported, isFalse);
    expect(sundayWeekStart.unsupportedReason, contains('Monday-based'));

    expect(
      () => parser.parse(
        'BEGIN:VCALENDAR\n'
        'BEGIN:VEVENT\n'
        'UID:bad-date@example\n'
        'SUMMARY:Impossible date\n'
        'DTSTART:20261340T250000Z\n'
        'DTEND:20261340T260000Z\n'
        'END:VEVENT\n'
        'END:VCALENDAR\n',
      ),
      throwsFormatException,
    );
  });

  test('ICS parser caps oversized input and event counts', () {
    final parser = IcsCalendarParser();

    expect(
      () => parser.parse(
        List.filled(
          IcsCalendarParser.maxSourceCharacters + 1,
          'x',
        ).join(),
      ),
      throwsFormatException,
    );

    final buffer = StringBuffer('BEGIN:VCALENDAR\n');
    for (var index = 0; index <= IcsCalendarParser.maxEvents; index++) {
      buffer
        ..writeln('BEGIN:VEVENT')
        ..writeln('UID:cap-$index@example')
        ..writeln('SUMMARY:Capacity test')
        ..writeln('DTSTART:20260928T090000Z')
        ..writeln('DTEND:20260928T100000Z')
        ..writeln('END:VEVENT');
    }
    buffer.writeln('END:VCALENDAR');

    expect(() => parser.parse(buffer.toString()), throwsFormatException);
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
    final changedExport = IcsCalendarParser().parse(
      'BEGIN:VCALENDAR\n'
      'BEGIN:VEVENT\n'
      'UID:dedupe-1@example\n'
      'SUMMARY:Imported class moved\n'
      'DTSTART:20260930T110000Z\n'
      'DTEND:20260930T120000Z\n'
      'END:VEVENT\n'
      'END:VCALENDAR\n',
    ).events.single;
    final second = await viewModel.importIcsEvents([changedExport]);

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
    await _pumpBounded(tester);

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

  testWidgets('ICS preview renders wall-clock time in the event TZID',
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
              name: 'new-york.ics',
              content: 'BEGIN:VCALENDAR\n'
                  'BEGIN:VEVENT\n'
                  'UID:tz-preview@example\n'
                  'SUMMARY:NY meeting\n'
                  'DTSTART;TZID=America/New_York:20260930T090000\n'
                  'DTEND;TZID=America/New_York:20260930T100000\n'
                  'END:VEVENT\n'
                  'END:VCALENDAR\n',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('choose-ics-file')));
    await _pumpBounded(tester);

    expect(
      find.text('30/09/2026 · 09:00–10:00 · America/New_York'),
      findsOneWidget,
    );
  });

  testWidgets('the entire From and To cards change their time values',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = DriftScheduleRepository(database);
    final viewModel = JadwalViewModel(repository);
    addTearDown(viewModel.dispose);
    await viewModel.initialize();
    await Future<void>.delayed(Duration.zero);

    var calls = 0;
    Future<TimeOfDay?> picker(
      BuildContext context,
      TimeOfDay initialTime,
    ) async {
      calls++;
      return calls == 1
          ? const TimeOfDay(hour: 14, minute: 30)
          : const TimeOfDay(hour: 17, minute: 45);
    }

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: TambahJadwalScreen(pickTime: picker),
          ),
        ),
      ),
    );
    await _pumpBounded(tester);

    final from = find.byKey(const Key('from-time-card'));
    await tester.ensureVisible(from);
    await tester.tapAt(tester.getTopLeft(from) + const Offset(8, 8));
    await _pumpBounded(tester);
    expect(find.text('14:30'), findsOneWidget);

    final to = find.byKey(const Key('to-time-card'));
    await tester.ensureVisible(to);
    await tester.tapAt(tester.getBottomRight(to) - const Offset(8, 8));
    await _pumpBounded(tester);
    expect(find.text('17:45'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('calendar swipes change month without leaving Schedule',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = DriftScheduleRepository(database);
    final viewModel = JadwalViewModel(repository);
    addTearDown(viewModel.dispose);
    await viewModel.initialize();
    await Future<void>.delayed(Duration.zero);
    viewModel.selectDate(DateTime(2026, 9, 1));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: JadwalHarianScreen(onSwitchTab: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('September 2026'), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('month-calendar-swipe-area')),
      const Offset(-320, 0),
    );
    await _pumpBounded(tester);

    expect(viewModel.selectedDate, DateTime(2026, 10, 1));
    expect(find.text('October 2026'), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('month-calendar-swipe-area')),
      const Offset(320, 0),
    );
    await _pumpBounded(tester);

    expect(viewModel.selectedDate, DateTime(2026, 9, 1));
    expect(find.text('September 2026'), findsOneWidget);
  });

  testWidgets('root body and bottom bar swipe through navigation tabs',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(TaktApp(database: database));
    await _pumpBounded(tester);

    expect(find.text('This week at a glance'), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('root-tab-swipe-area')),
      const Offset(-420, 0),
    );
    await _pumpBounded(tester);
    expect(find.text('My Schedule'), findsOneWidget);

    final scheduleContext =
        tester.element(find.byType(JadwalHarianScreen));
    final schedule = Provider.of<JadwalViewModel>(
      scheduleContext,
      listen: false,
    );
    schedule.selectDate(DateTime(2026, 9, 1));
    await tester.pump();

    await tester.drag(
      find.byKey(const Key('month-calendar-swipe-area')),
      const Offset(-320, 0),
    );
    await _pumpBounded(tester);

    expect(find.text('My Schedule'), findsOneWidget);
    expect(find.text('October 2026'), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('bottom-nav-swipe-area')),
      const Offset(-420, 0),
    );
    await _pumpBounded(tester);
    expect(find.text('Analyze Competition'), findsOneWidget);
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
