import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:takt_mobile/config/revenuecat_config.dart';
import 'package:takt_mobile/data/database/app_database.dart';
import 'package:takt_mobile/data/remote/competition_api_client.dart';
import 'package:takt_mobile/data/repositories/analysis_repository.dart';
import 'package:takt_mobile/data/repositories/drift_schedule_repository.dart';
import 'package:takt_mobile/data/repositories/saved_plan_repository.dart';
import 'package:takt_mobile/models/active_accepted_block.dart';
import 'package:takt_mobile/models/analysis_snapshot.dart';
import 'package:takt_mobile/models/competition_analysis_wire.dart';
import 'package:takt_mobile/models/enums.dart';
import 'package:takt_mobile/models/saved_plan.dart';
import 'package:takt_mobile/models/saved_plan_revision.dart';
import 'package:takt_mobile/monetization/revenuecat_contract.dart';
import 'package:takt_mobile/monetization/revenuecat_gateway.dart';
import 'package:takt_mobile/monetization/revenuecat_service.dart';
import 'package:takt_mobile/main.dart';
import 'package:takt_mobile/screens/analisis_kompetisi_screen.dart';
import 'package:takt_mobile/screens/home_screen.dart';
import 'package:takt_mobile/screens/jadwal_harian_screen.dart';
import 'package:takt_mobile/screens/rekomendasi_jadwal_screen.dart';
import 'package:takt_mobile/screens/rencana_screen.dart';
import 'package:takt_mobile/screens/review_brief_screen.dart';
import 'package:takt_mobile/screens/saved_plan_detail_screen.dart';
import 'package:takt_mobile/theme/app_theme.dart';
import 'package:takt_mobile/viewmodels/analisis_view_model.dart';
import 'package:takt_mobile/viewmodels/jadwal_view_model.dart';
import 'package:takt_mobile/viewmodels/saved_plan_detail_view_model.dart';
import 'package:takt_mobile/viewmodels/saved_plans_view_model.dart';

import 'support/decision_fixture.dart';
import 'support/release_7b_fixture.dart';

const _frameKey = Key('release-7b-evidence-frame');
const _evidenceNames = <String>[
  '01-hero-overview.png',
  '02-my-schedule.png',
  '03-analyze-competition.png',
  '04-conflict-provenance.png',
  '05-decision-report.png',
  '06-alternative-candidate.png',
  '07-saved-plan-accepted.png',
  '08-stale-reevaluate.png',
  '09-accepted-commitment.png',
];

bool get _shouldCaptureGoldens =>
    Platform.environment['TAKT_7B_CAPTURE_GOLDENS'] == '1';

Directory get _auditDirectory => Directory(
      Platform.environment['TAKT_7B_AUDIT_DIR'] ?? 'build/7b-audit',
    );

Widget _frame(Widget child, {double textScale = 1}) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          backgroundColor: C.bg,
          body: SafeArea(
            child: RepaintBoundary(
              key: _frameKey,
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpBounded(
  WidgetTester tester, {
  int frames = 12,
}) async {
  for (var index = 0; index < frames; index++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<void> _capture(WidgetTester tester, String filename) async {
  await _pumpBounded(tester);
  expect(tester.takeException(), isNull);
  if (!_shouldCaptureGoldens) return;
  await expectLater(
    find.byKey(_frameKey),
    matchesGoldenFile('release_7b_goldens/$filename'),
  );
}

void _phoneViewport(WidgetTester tester, {double scale = 1}) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
}

void _compactViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 720);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
}

void _resetViewport(WidgetTester tester) {
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
  tester.platformDispatcher.clearTextScaleFactorTestValue();
}

void main() {
  testWidgets('7B synthetic screenshot evidence covers critical product states',
      (tester) async {
    _phoneViewport(tester);
    addTearDown(() => _resetViewport(tester));
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.initialize();
    final scheduleRepository = DriftScheduleRepository(
      db,
      closeDatabaseOnDispose: false,
    );
    final schedule = JadwalViewModel(
      scheduleRepository,
      closeScheduleRepositoryOnDispose: false,
    );
    await schedule.initialize();
    addTearDown(schedule.dispose);
    addTearDown(scheduleRepository.close);
    addTearDown(db.close);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: schedule,
        child: _frame(
          HomeScreen(onLihatJadwal: () {}),
        ),
      ),
    );
    await _capture(tester, _evidenceNames[0]);

    final scheduleDay = DateTime(2026, 10, 1);
    expect(
      await schedule.tambah(
        title: 'Synthetic architecture review',
        category: 'lomba',
        start: DateTime(2026, 10, 1, 13),
        end: DateTime(2026, 10, 1, 14, 30),
      ),
      isTrue,
    );
    schedule.selectDate(scheduleDay);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: schedule,
        child: _frame(
          JadwalHarianScreen(onSwitchTab: (_) {}, onAdd: () {}),
        ),
      ),
    );
    await _capture(tester, _evidenceNames[1]);

    final analysis = AnalisisViewModel(
      apiClient: _NoopApiClient(),
      repository: _NoopAnalysisRepository(),
    );
    addTearDown(analysis.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: analysis,
        child: _frame(
          const AnalisisKompetisiScreen(continuation: false),
        ),
      ),
    );
    await _capture(tester, _evidenceNames[2]);

    await tester.pumpWidget(
      _frame(
        ReviewBriefScreen(
          response: releaseConflictReviewFixture(),
          onAddSource: () {},
          onNewAnalysis: () {},
        ),
      ),
    );
    await _capture(tester, _evidenceNames[3]);

    final revenueCat = RevenueCatService(
      config: RevenueCatConfig.validate(
        appEnv: 'test_store',
        apiKey: 'test_release_audit',
        buildMode: AppBuildMode.debug,
      ),
      gateway: _ActiveRevenueCatGateway(),
    );
    await revenueCat.initialize();
    addTearDown(revenueCat.dispose);

    await tester.pumpWidget(
      _frame(
        RekomendasiJadwalScreen(
          session: testSession(),
          currentInputRevision: 3,
          revenueCatService: revenueCat,
          onAccept: (_, _) async {},
          onEditConstraints: (_) {},
          onIgnore: (_) {},
        ),
      ),
    );
    await _capture(tester, _evidenceNames[4]);

    final chooseAlternative = find.byKey(const Key('choose-later-option'));
    await tester.ensureVisible(chooseAlternative);
    await _pumpBounded(tester);
    await tester.tap(chooseAlternative);
    await _pumpBounded(tester);
    expect(find.text('Your selected option'), findsOneWidget);
    await _capture(tester, _evidenceNames[5]);

    final acceptedRepo = _StaticSavedPlanRepository(
      summaries: [releaseSavedPlanSummary(stale: false)],
      detail: releaseSavedPlanDetail(stale: false),
    );
    final plans = SavedPlansViewModel(
      acceptedRepo,
      closeRepositoryOnDispose: false,
    );
    await plans.initialize();
    addTearDown(plans.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: plans,
        child: _frame(
          RencanaScreen(onOpen: (_) {}),
        ),
      ),
    );
    await _pumpBounded(tester);
    expect(find.text('ACCEPTED'), findsOneWidget);
    await _capture(tester, _evidenceNames[6]);

    final staleRepo = _StaticSavedPlanRepository(
      summaries: [releaseSavedPlanSummary(stale: true)],
      detail: releaseSavedPlanDetail(stale: true),
    );
    final detailVm = SavedPlanDetailViewModel(staleRepo);
    addTearDown(detailVm.dispose);
    await tester.pumpWidget(
      _frame(
        SavedPlanDetailScreen(
          savedPlanId: 'saved-plan-demo',
          viewModel: detailVm,
          onReevaluate: (_) async {},
          onViewSchedule: (_) {},
        ),
      ),
    );
    await _pumpBounded(tester);
    expect(find.byKey(const Key('persisted-evaluation-stale')), findsOneWidget);
    expect(find.text('Re-evaluate'), findsOneWidget);
    await _capture(tester, _evidenceNames[7]);

    await tester.dragUntilVisible(
      find.text('Accepted schedule'),
      find.byType(ListView),
      const Offset(0, -240),
    );
    await _pumpBounded(tester);
    expect(find.textContaining('synthetic-work-window'), findsOneWidget);
    await _capture(tester, _evidenceNames[8]);

    if (_shouldCaptureGoldens) {
      final goldenDirectory = Directory('test/release_7b_goldens');
      final files = _evidenceNames
          .map((name) => File('${goldenDirectory.path}/$name'))
          .toList(growable: false);
      expect(
        files.every((file) => file.existsSync() && file.lengthSync() > 0),
        isTrue,
      );
    }

    final manifest = {
      'format': '7b-mobile-evidence-v1',
      'synthetic_data_only': true,
      'capture_mode': _shouldCaptureGoldens ? 'flutter_golden_update' : 'assertions_only',
      'screenshots': _evidenceNames,
      'fixture_domains': ['example.test'],
      'states': [
        'hero_overview',
        'my_schedule',
        'analyze_competition',
        'conflict_provenance',
        'decision_report',
        'alternative_candidate',
        'saved_plan_accepted',
        'stale_reevaluate',
        'accepted_commitment',
      ],
    };
    await _auditDirectory.create(recursive: true);
    await File('${_auditDirectory.path}/manifest.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
      flush: true,
    );
  });

  testWidgets('7B critical root surfaces remain usable at 320px and 2x text',
      (tester) async {
    _compactViewport(tester);
    addTearDown(() => _resetViewport(tester));

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      TaktApp(database: db),
    );
    for (final tab in ['Home', 'Schedule', 'Analysis', 'Plans']) {
      await tester.tap(find.text(tab));
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      expect(tester.takeException(), isNull, reason: '$tab must not overflow');
    }
  });
}

final class _StaticSavedPlanRepository implements SavedPlanRepository {
  _StaticSavedPlanRepository({
    required this.summaries,
    required this.detail,
  });

  final List<SavedPlanSummary> summaries;
  final SavedPlanDetail detail;

  @override
  Future<void> initialize() async {}

  @override
  Stream<List<SavedPlanSummary>> watchSummaries() => Stream.value(summaries);

  @override
  Future<List<SavedPlanSummary>> listSummaries() async => summaries;

  @override
  Future<SavedPlan?> planForCompetition(String competitionId) async {
    for (final summary in summaries) {
      if (summary.plan.competitionId == competitionId) return summary.plan;
    }
    return null;
  }

  @override
  Future<SavedPlanRevision> acceptEvaluation({
    required String evaluationId,
    required String candidateId,
    required SelectionSource selectionSource,
  }) {
    throw UnsupportedError('read-only release evidence fixture');
  }

  @override
  Future<List<ActiveAcceptedBlock>> activeAcceptedBlocks({
    String? excludingSavedPlanId,
  }) async =>
      const [];

  @override
  Future<SavedPlanDetail?> loadDetail(String savedPlanId) async =>
      savedPlanId == detail.summary.plan.id ? detail : null;

  @override
  Future<void> updateTaskProgress({
    required String savedPlanTaskId,
    required int progressPercent,
    int? actualMinutes,
    bool clearActualMinutes = false,
  }) async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> close() async {}
}

final class _ActiveRevenueCatGateway implements RevenueCatGateway {
  @override
  Future<void> configure({required String apiKey}) async {}

  @override
  Future<RevenueCatCustomerSnapshot> getCustomerInfo() async =>
      const RevenueCatCustomerSnapshot(
        activeEntitlementIds: {RevenueCatContract.entitlementIdentifier},
      );

  @override
  Future<RevenueCatPackageSnapshot?> getPackage({
    required String offeringIdentifier,
    required String packageIdentifier,
  }) async =>
      RevenueCatPackageSnapshot(
        offeringIdentifier: offeringIdentifier,
        packageIdentifier: packageIdentifier,
        productIdentifier: RevenueCatContract.testStoreProductIdentifier,
        priceString: r'$0.99',
      );

  @override
  Future<RevenueCatCustomerSnapshot> purchasePackage({
    required String offeringIdentifier,
    required String packageIdentifier,
  }) =>
      getCustomerInfo();

  @override
  Future<RevenueCatCustomerSnapshot> restorePurchases() => getCustomerInfo();
}

final class _NoopApiClient implements CompetitionApiClient {
  @override
  Future<CompetitionAnalysisTransportResult> analyzePdf({
    required String competitionId,
    required String documentId,
    required String filename,
    required Uint8List bytes,
    required AnalysisSourceMetadata source,
    AnalysisContinuationContext? continuation,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<CompetitionAnalysisTransportResult> analyzeUrl({
    required String competitionId,
    required String url,
    required AnalysisSourceMetadata source,
    AnalysisContinuationContext? continuation,
  }) {
    throw UnimplementedError();
  }

  @override
  void close() {}
}

final class _NoopAnalysisRepository implements AnalysisRepository {
  @override
  Future<void> initialize() async {}

  @override
  Future<AnalysisSnapshot?> latestSnapshot(String competitionId) async => null;

  @override
  Future<AnalysisSnapshot> persistResponse({
    required String originalBody,
    required CompetitionAnalyzeResponseWire response,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<AnalysisSnapshot>> snapshotsForCompetition(
    String competitionId,
  ) async =>
      const [];

  @override
  Future<void> close() async {}
}
