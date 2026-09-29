import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takt_mobile/data/database/app_database.dart';
import 'package:takt_mobile/data/repositories/drift_schedule_repository.dart';
import 'package:takt_mobile/main.dart';
import 'package:takt_mobile/models/competition_brief.dart';
import 'package:takt_mobile/models/enums.dart';
import 'package:takt_mobile/screens/rekomendasi_jadwal_screen.dart';
import 'package:takt_mobile/theme/app_theme.dart';

void main() {
  testWidgets('renders the preserved primary navigation', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = DriftScheduleRepository(database);
    addTearDown(repository.close);

    await tester.pumpWidget(TaktApp(scheduleRepository: repository));
    await tester.pumpAndSettle();

    expect(find.text('Beranda'), findsOneWidget);
    expect(find.text('Jadwal'), findsOneWidget);
    expect(find.text('Analisis'), findsOneWidget);
    expect(find.text('Rencana'), findsOneWidget);
    expect(find.text('Ringkasan pekan ini'), findsOneWidget);
    expect(find.text('Batas proyek / hari'), findsOneWidget);
    expect(find.text('Tersedia'), findsNothing);
    expect(find.text('Welcome, Raka'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('unknown domain values fail closed and absent feasibility stays null', () {
    final parsers = <Object? Function(String)>[
      CommitmentType.fromWire,
      ExceptionAction.fromWire,
      ReadinessStatus.fromWire,
      FeasibilityStatus.fromWire,
      ReevaluationKind.fromWire,
      SelectionSource.fromWire,
    ];
    for (final parse in parsers) {
      for (final value in ['', 'UNKNOWN', 'feasible', ' FEASIBLE ']) {
        expect(() => parse(value), throwsStateError);
      }
    }
    expect(FeasibilityStatus.fromWire(null), isNull);
    expect(FeasibilityStatus.fromWire('FEASIBLE'), FeasibilityStatus.feasible);
  });

  testWidgets('pending recommendation fits a phone and cannot submit a plan',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var submitted = false;
    var wentBack = false;

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: RekomendasiJadwalScreen(
          brief: CompetitionBrief.demo(),
          onSubmitDone: () => submitted = true,
          onBack: () => wentBack = true,
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Tidak ada slot kosong'), findsNothing);
    expect(find.textContaining('Rekomendasi belum tersedia'), findsOneWidget);

    final pendingButton = find.text('Belum tersedia').last;
    await tester.ensureVisible(pendingButton);
    await tester.pumpAndSettle();
    await tester.tap(pendingButton);
    await tester.pump();
    expect(submitted, isFalse);

    final backButton = find.byIcon(Icons.chevron_left);
    await tester.ensureVisible(backButton);
    await tester.pumpAndSettle();
    await tester.tap(backButton);
    await tester.pump();
    expect(wentBack, isTrue);
    expect(tester.takeException(), isNull);
  });
}
