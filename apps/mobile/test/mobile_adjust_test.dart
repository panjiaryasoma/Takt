import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:takt_mobile/calendar/ics_import.dart';
import 'package:takt_mobile/data/database/app_database.dart';
import 'package:takt_mobile/data/repositories/drift_schedule_repository.dart';
import 'package:takt_mobile/data/repositories/schedule_repository.dart';
import 'package:takt_mobile/main.dart';
import 'package:takt_mobile/screens/ics_import_screen.dart';
import 'package:takt_mobile/screens/jadwal_harian_screen.dart';
import 'package:takt_mobile/screens/jadwal_ringkasan_screen.dart';
import 'package:takt_mobile/screens/tambah_jadwal_screen.dart';
import 'package:takt_mobile/theme/app_theme.dart';
import 'package:takt_mobile/viewmodels/jadwal_view_model.dart';

final class _UnusedScheduleRepository implements ScheduleRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw StateError(
      'UI-only test unexpectedly touched ScheduleRepository: '
      '${invocation.memberName}',
    );
  }
}

Future<void> _pumpBounded(
  WidgetTester tester, {
  int frames = 12,
}) async {
  for (var index = 0; index < frames; index++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

void main() {
  test('in-app branding uses the transparent Takt mark', () {
    expect(File('assets/branding/logo_in_app.png').existsSync(), isTrue);
    expect(C.logoAsset, 'assets/branding/logo_in_app.png');
    expect(C.logoAsset, isNot('assets/branding/logo.png'));
  });

  test('Android launcher and native splash use the canonical Takt logo', () {
    expect(File('assets/branding/logo.png').existsSync(), isTrue);
    expect(File('assets/branding/logo.jpg').existsSync(), isFalse);

    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final splash =
        File('android/app/src/main/res/drawable/launch_background.xml')
            .readAsStringSync();
    final android12 =
        File('android/app/src/main/res/values-v31/styles.xml')
            .readAsStringSync();

    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(File('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png').existsSync(), isTrue);
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
        'ios/Runner/Assets.xcassets/TaktLogo.imageset/takt_logo.png',
      ).existsSync(),
      isTrue,
    );
    expect(launchScreen, contains('image="TaktLogo"'));
    expect(launchScreen, contains('red="0.1764705882"'));
    expect(imageSet, contains('"filename" : "takt_logo.png"'));
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
    addTearDown(repository.close);

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

  testWidgets('ICS import screen requires file selection before import',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const IcsImportScreen(),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('choose-ics-file')), findsOneWidget);
    expect(find.byKey(const Key('import-selected-ics')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBounded(tester, frames: 2);
  });

  testWidgets('FIXED and FLEXIBLE copy matches planning semantics',
      (tester) async {
    final viewModel = JadwalViewModel(
      _UnusedScheduleRepository(),
      closeScheduleRepositoryOnDispose: false,
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: TambahJadwalScreen()),
        ),
      ),
    );
    await _pumpBounded(tester);

    expect(
      find.text('Scheduled time is treated as unavailable during planning.'),
      findsOneWidget,
    );

    await tester.tap(find.text('FLEXIBLE'));
    await tester.pump();

    expect(
      find.textContaining(
        'its currently scheduled time is still treated as unavailable during planning',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Takt does not move it automatically'),
      findsOneWidget,
    );
    expect(find.textContaining('Takt can move'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBounded(tester, frames: 2);
  });

  testWidgets('Add Schedule keeps critical controls reachable at 320px and 2x text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewModel = JadwalViewModel(
      _UnusedScheduleRepository(),
      closeScheduleRepositoryOnDispose: false,
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
              ),
              child: const Scaffold(body: TambahJadwalScreen()),
            ),
          ),
        ),
      ),
    );
    await _pumpBounded(tester);

    final save = find.byKey(const Key('save-schedule'));
    await tester.ensureVisible(save);
    await _pumpBounded(tester, frames: 2);
    expect(save, findsOneWidget);
    expect(find.byKey(const Key('commitment-type-explanation')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBounded(tester, frames: 2);
  });

  testWidgets('the entire From and To cards change their time values',
      (tester) async {
    final viewModel = JadwalViewModel(
      _UnusedScheduleRepository(),
      closeScheduleRepositoryOnDispose: false,
    );
    addTearDown(viewModel.dispose);

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

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBounded(tester, frames: 2);
  });

  testWidgets('calendar swipes change month without leaving Schedule',
      (tester) async {
    final viewModel = JadwalViewModel(
      _UnusedScheduleRepository(),
      closeScheduleRepositoryOnDispose: false,
    );
    addTearDown(viewModel.dispose);
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

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBounded(tester, frames: 2);
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

    // Dispose TaktApp-owned providers/repositories before the database teardown.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBounded(tester);
  });

  testWidgets('system back closes Add Schedule before the root route',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(TaktApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schedule'));
    await _pumpBounded(tester);
    await tester.tap(find.text('Add'));
    await _pumpBounded(tester);
    expect(find.text('Add Schedule'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await _pumpBounded(tester);
    expect(find.text('Add Schedule'), findsNothing);
    expect(find.text('My Schedule'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBounded(tester, frames: 2);
  });

  testWidgets('cancelled recurrence stays visible without blocking capacity',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = DriftScheduleRepository(database);
    final viewModel = JadwalViewModel(repository);
    addTearDown(viewModel.dispose);
    addTearDown(repository.close);

    await viewModel.initialize();
    await Future<void>.delayed(Duration.zero);
    await viewModel.tambahRutin(
      title: 'Cancelled class',
      weekdays: {DateTime.wednesday},
      jamMulai: 9,
      menitMulai: 0,
      jamSelesai: 10,
      menitSelesai: 0,
      mulaiDari: DateTime(2026, 9, 30),
    );
    await Future<void>.delayed(Duration.zero);
    final occurrence = viewModel.itemsOn(DateTime(2026, 9, 30)).single;
    expect(await viewModel.cancelOccurrence(occurrence), isTrue);
    await Future<void>.delayed(Duration.zero);
    viewModel.selectDate(DateTime(2026, 9, 30));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: JadwalHarianScreen(onSwitchTab: (_) {})),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('cancelled occurrence'), findsOneWidget);
    expect(find.textContaining('does not block planning'), findsOneWidget);
    expect(find.byKey(const Key('schedule-empty-state')), findsNothing);
    expect(viewModel.scheduledMinutesOn(DateTime(2026, 9, 30)), 0);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBounded(tester, frames: 2);
  });

  testWidgets('Schedule daily and weekly remain reachable at 320px and 2x text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewModel = JadwalViewModel(
      _UnusedScheduleRepository(),
      closeScheduleRepositoryOnDispose: false,
    );
    addTearDown(viewModel.dispose);
    viewModel.selectDate(DateTime(2026, 9, 30));

    Widget shell(Widget child) => ChangeNotifierProvider.value(
          value: viewModel,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                ),
                child: Scaffold(body: child),
              ),
            ),
          ),
        );

    await tester.pumpWidget(shell(JadwalHarianScreen(onSwitchTab: (_) {})));
    await _pumpBounded(tester);
    expect(find.text('My Schedule'), findsOneWidget);
    expect(find.text('Daily Schedule'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      shell(JadwalRingkasanScreen(
        onSwitchTab: (_) {},
        now: DateTime(2026, 9, 30, 10),
      )),
    );
    await _pumpBounded(tester);
    expect(find.text('Weekly Summary'), findsWidgets);
    expect(find.byKey(const Key('weekly-time-type-explanation')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBounded(tester, frames: 2);
  });

  testWidgets('weekly summary highlights device-local today only in current week',
      (tester) async {
    final viewModel = JadwalViewModel(
      _UnusedScheduleRepository(),
      closeScheduleRepositoryOnDispose: false,
    );
    addTearDown(viewModel.dispose);
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

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBounded(tester, frames: 2);
  });
}
