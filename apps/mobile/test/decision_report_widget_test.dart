import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takt_mobile/data/database/app_database.dart';
import 'package:takt_mobile/data/repositories/drift_analysis_repository.dart';
import 'package:takt_mobile/data/repositories/drift_schedule_repository.dart';
import 'package:takt_mobile/config/revenuecat_config.dart';
import 'package:takt_mobile/main.dart';
import 'package:takt_mobile/models/decision_intent.dart';
import 'package:takt_mobile/models/enums.dart';
import 'package:takt_mobile/models/evaluation_session.dart';
import 'package:takt_mobile/monetization/revenuecat_contract.dart';
import 'package:takt_mobile/monetization/revenuecat_gateway.dart';
import 'package:takt_mobile/monetization/revenuecat_service.dart';
import 'package:takt_mobile/screens/rekomendasi_jadwal_screen.dart';
import 'package:takt_mobile/theme/app_theme.dart';

import 'support/decision_fixture.dart';

Widget report(
  EvaluationSession? session, {
  int revision = 3,
  AcceptCandidateHandler? onAccept,
  ValueChanged<EditConstraintsIntent>? onEdit,
  ValueChanged<IgnoreRecommendationIntent>? onIgnore,
  RevenueCatService? revenueCatService,
  VoidCallback? onOpenPro,
  double scale = 1,
  bool acceptancePersistencePending = false,
  String? acceptancePersistenceMessage,
  Future<void> Function()? onRetryAcceptanceSave,
  VoidCallback? onCancelPendingAcceptance,
}) =>
    MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: RekomendasiJadwalScreen(
              session: session,
              currentInputRevision: revision,
              revenueCatService: revenueCatService,
              onOpenPro: onOpenPro,
              onAccept: onAccept,
              onEditConstraints: onEdit,
              onIgnore: onIgnore,
              acceptancePersistencePending: acceptancePersistencePending,
              acceptancePersistenceMessage: acceptancePersistenceMessage,
              onRetryAcceptanceSave: onRetryAcceptanceSave,
              onCancelPendingAcceptance: onCancelPendingAcceptance,
            ),
          ),
        ),
      ),
    );

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('phone layout separates readiness, feasibility, primary and selected alternative', (tester) async {
    final service = await _initializedRevenueCat(active: true);
    addTearDown(service.dispose);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(report(testSession(), scale: 1.5,
        revenueCatService: service, onAccept: (_, _) async {}));
    expect(find.text('Readiness'), findsOneWidget);
    expect(find.text('Feasibility'), findsOneWidget);
    expect(find.text('Tight capacity'), findsOneWidget);
    expect(find.text('System primary recommendation'), findsOneWidget);
    expect(find.text('Suggested schedule · Not added to calendar'), findsWidgets);
    expect(find.byKey(const Key('buffer-$primaryId')), findsOneWidget);
    expect(find.byKey(const Key('buffer-$alternativeId')), findsOneWidget);
    expect(find.text('Recommendation'), findsOneWidget);
    expect(find.byKey(const Key('recommendation-advisory-copy')), findsOneWidget);
    expect(find.text('EFFORT_OVERRUN_BREAKS_PLAN'), findsNothing);
    expect(find.textContaining('not your ability'), findsOneWidget);
    expect(find.textContaining('Next work: Build prototype'), findsNWidgets(2));
    await tapKey(tester, 'choose-$alternativeId');
    expect(find.descendant(of: find.byKey(const Key('candidate-primary-option')),
        matching: find.text('Your selected option')), findsNothing);
    expect(find.descendant(of: find.byKey(const Key('candidate-later-option')),
        matching: find.text('Your selected option')), findsOneWidget);
    expect(find.text('System primary recommendation'), findsOneWidget);
    expect(find.text('Saved'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('critical Decision Report semantics survive 320px width at 2x text', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(report(
      testSession(alternatives: false),
      scale: 2,
      onAccept: (_, _) async {},
      onEdit: (_) {},
      onIgnore: (_) {},
    ));
    await tester.pumpAndSettle();

    expect(find.text('Readiness'), findsOneWidget);
    expect(find.text('Feasibility'), findsOneWidget);
    expect(find.text('Recommendation'), findsOneWidget);
    expect(find.byKey(const Key('accept-candidate')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('accept-candidate')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('accept-candidate'))).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmation hands off the exact alternative/session once with no persistence claim', (tester) async {
    final service = await _initializedRevenueCat(active: true);
    addTearDown(service.dispose);
    final session = testSession();
    final gate = Completer<void>();
    final calls = <(EvaluationSession, AcceptCandidateIntent)>[];
    await tester.pumpWidget(report(session, revenueCatService: service,
        onAccept: (s, intent) {
      calls.add((s, intent));
      return gate.future;
    }));
    await tapKey(tester, 'choose-$alternativeId');
    await tapKey(tester, 'accept-candidate');
    expect(calls, isEmpty);
    expect(find.text('Accept this option?'), findsOneWidget);
    expect(find.text('Your selected alternative'), findsOneWidget);
    await tapKey(tester, 'confirm-accept');
    expect(calls, hasLength(1));
    expect(calls.single.$1, same(session));
    expect(calls.single.$2.candidateId, alternativeId);
    expect(calls.single.$2.selectionSource, SelectionSource.alternative);
    expect(find.byKey(const Key('handoff-pending')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('accept-candidate'))).onPressed, isNull);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('handoff-complete')), findsOneWidget);
    expect(find.text('Saved'), findsNothing);
    expect(find.text('Added to calendar'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pending acceptance shows retry/cancel persistence without a second decision',
      (tester) async {
    var retries = 0;
    var cancels = 0;
    await tester.pumpWidget(
      report(
        testSession(alternatives: false),
        onAccept: (_, _) async {},
        onEdit: (_) {},
        onIgnore: (_) {},
        acceptancePersistencePending: true,
        acceptancePersistenceMessage:
            'The confirmed choice could not be committed locally.',
        onRetryAcceptanceSave: () async => retries++,
        onCancelPendingAcceptance: () => cancels++,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Acceptance is confirmed but not saved'), findsOneWidget);
    expect(find.text('Retry acceptance save'), findsOneWidget);
    expect(find.text('Cancel pending acceptance'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('accept-candidate'))).onPressed,
      isNull,
    );

    final retrySave = find.text('Retry acceptance save');
    await tester.ensureVisible(retrySave);
    await tester.tap(retrySave);
    await tester.pump();
    expect(retries, 1);
    expect(cancels, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('free keeps primary visible and locks alternative candidates',
      (tester) async {
    final service = await _initializedRevenueCat(active: false);
    addTearDown(service.dispose);
    var openedPro = 0;

    await tester.pumpWidget(report(
      testSession(),
      revenueCatService: service,
      onOpenPro: () => openedPro++,
      onAccept: (_, _) async {},
    ));

    expect(find.text('System primary recommendation'), findsOneWidget);
    expect(find.byKey(const Key('candidate-$primaryId')), findsOneWidget);
    expect(find.byKey(const Key('candidate-$alternativeId')), findsNothing);
    expect(find.byKey(const Key('alternatives-locked')), findsOneWidget);
    expect(find.byKey(const Key('choose-$alternativeId')), findsNothing);
    expect(find.byKey(const Key('buffer-$primaryId')), findsOneWidget);
    expect(find.byKey(const Key('buffer-$alternativeId')), findsNothing);

    await tapKey(tester, 'open-pro-alternatives');
    expect(openedPro, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading and first entitlement error fail closed',
      (tester) async {
    final gate = Completer<RevenueCatCustomerSnapshot>();
    final loadingGateway = _DecisionRevenueCatGateway(
      active: true,
      customerInfoFuture: gate.future,
    );
    final loading = _revenueCatService(loadingGateway);
    addTearDown(loading.dispose);
    final initializing = loading.initialize();

    expect(loading.entitlement.sync, EntitlementSync.loading);
    await tester.pumpWidget(
      report(testSession(), revenueCatService: loading),
    );
    expect(find.byKey(const Key('candidate-$alternativeId')), findsNothing);
    expect(find.byKey(const Key('alternatives-locked')), findsOneWidget);

    gate.complete(
      const RevenueCatCustomerSnapshot(activeEntitlementIds: {}),
    );
    await initializing;

    final failed = await _initializedRevenueCat(
      active: true,
      customerInfoError: StateError('simulated CustomerInfo failure'),
    );
    addTearDown(failed.dispose);
    expect(failed.entitlement.sync, EntitlementSync.error);

    await tester.pumpWidget(
      report(testSession(), revenueCatService: failed),
    );
    expect(find.byKey(const Key('candidate-$alternativeId')), findsNothing);
    expect(find.byKey(const Key('alternatives-locked')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('entitlement loss cannot confirm a previously selected alternative',
      (tester) async {
    final gateway = _DecisionRevenueCatGateway(active: true);
    final service = _revenueCatService(gateway);
    addTearDown(service.dispose);
    await service.initialize();

    final calls = <AcceptCandidateIntent>[];
    await tester.pumpWidget(report(
      testSession(),
      revenueCatService: service,
      onAccept: (_, intent) async => calls.add(intent),
    ));

    await tapKey(tester, 'choose-$alternativeId');
    await tapKey(tester, 'accept-candidate');
    expect(find.text('Your selected alternative'), findsOneWidget);

    gateway.active = false;
    await service.refreshEntitlement();
    await tester.pump();

    await tapKey(tester, 'confirm-accept');
    expect(calls, isEmpty);
    expect(find.byKey(const Key('handoff-pending')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TaktApp wires Home Takt Pro entry to RevenueCat provider',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final schedule = DriftScheduleRepository(
      database,
      closeDatabaseOnDispose: false,
    );
    final service = await _initializedRevenueCat(active: false);
    addTearDown(service.dispose);
    addTearDown(schedule.close);
    addTearDown(database.close);

    await tester.pumpWidget(
      TaktApp(
        database: database,
        scheduleRepository: schedule,
        revenueCatService: service,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Takt Pro'));
    await tester.pumpAndSettle();

    expect(find.text('Unlock Takt Pro'), findsOneWidget);
    expect(find.text(r'Get lifetime access · $0.99'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel confirmation emits no intent', (tester) async {
    var calls = 0;
    await tester.pumpWidget(report(testSession(), onAccept: (_, _) async { calls++; }));
    await tapKey(tester, 'accept-candidate');
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byKey(const Key('confirm-accept')), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const Key('accept-candidate'))).onPressed, isNotNull);
  });

  testWidgets('session replacement at same revision closes the owned confirmation', (tester) async {
    var calls = 0;
    Future<void> accept(EvaluationSession s, AcceptCandidateIntent i) async { calls++; }
    await tester.pumpWidget(report(testSession(), onAccept: accept));
    await tapKey(tester, 'accept-candidate');
    await tester.pumpWidget(report(testSession(generation: 13), onAccept: accept));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm-accept')), findsNothing);
    expect(calls, 0);
    expect(find.text('Decision Report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('revision change clears pending confirmation and disables Accept', (tester) async {
    final session = testSession();
    var calls = 0;
    Future<void> accept(EvaluationSession s, AcceptCandidateIntent i) async { calls++; }
    await tester.pumpWidget(report(session, onAccept: accept));
    await tapKey(tester, 'accept-candidate');
    await tester.pumpWidget(report(session, revision: 4, onAccept: accept));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm-accept')), findsNothing);
    expect(find.byKey(const Key('stale-notice')), findsOneWidget);
    expect(find.byKey(const Key('session-outdated-notice')), findsOneWidget);
    expect(find.text('Your selected option'), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const Key('accept-candidate'))).onPressed, isNull);
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('infeasible exposes only edit and ignore, each hands off identity', (tester) async {
    EditConstraintsIntent? edit;
    IgnoreRecommendationIntent? ignore;
    await tester.pumpWidget(report(testSession(feasibility: 'NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS'),
        onEdit: (intent) => edit = intent, onIgnore: (intent) => ignore = intent));
    expect(find.text('Ready to evaluate'), findsOneWidget);
    expect(find.text('Not feasible under current constraints'), findsOneWidget);
    expect(find.byKey(const Key('accept-candidate')), findsNothing);
    expect(find.text('System primary recommendation'), findsNothing);
    await tapKey(tester, 'edit-constraints');
    expect(edit!.sessionId, 'session-12');
    expect(edit!.inputRevision, 3);
    expect(ignore, isNull);
    await tapKey(tester, 'ignore-recommendation');
    expect(ignore!.evaluationId, evaluationId);
    expect(find.text('Recommendation ignored. Your schedule has not changed.'), findsOneWidget);
  });

  const blockedCases = [
    (ReadinessStatus.needsReview, 'Needs review',
      'Schedule feasibility was not evaluated because some information still needs review.'),
    (ReadinessStatus.insufficientInformation, 'Insufficient information',
      'Schedule feasibility was not evaluated because required information is still insufficient.'),
    (ReadinessStatus.eligibilityBlocked, 'Participant requirements not met',
      'Schedule feasibility was not evaluated because participant requirements are not met.'),
    (ReadinessStatus.deadlinePassed, 'Submission deadline has passed',
      'Schedule feasibility was not evaluated because the submission deadline has passed.'),
  ];
  for (final (status, readinessLabel, explanation) in blockedCases) {
    testWidgets('${status.wire} explains the readiness gate without implying infeasibility', (tester) async {
      var decisions = 0;
      await tester.pumpWidget(report(testSession(readiness: status.wire),
          onAccept: (_, _) async { decisions++; },
          onEdit: (_) { decisions++; }, onIgnore: (_) { decisions++; }));
      expect(find.text(readinessLabel), findsOneWidget);
      expect(find.text('Not evaluated'), findsOneWidget);
      expect(find.text(explanation), findsOneWidget);
      expect(find.text('Not feasible under current constraints'), findsNothing);
      expect(find.text('System primary recommendation'), findsNothing);
      expect(find.byKey(const Key('accept-candidate')), findsNothing);
      expect(find.byKey(const Key('edit-constraints')), findsNothing);
      expect(find.byKey(const Key('ignore-recommendation')), findsNothing);
      expect(find.text('Schedule feasibility is waiting for information and requirements.'), findsNothing);
      expect(decisions, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('missing integration handlers cannot silently accept or edit', (tester) async {
    await tester.pumpWidget(report(testSession(alternatives: false)));
    expect(tester.widget<FilledButton>(find.byKey(const Key('accept-candidate'))).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('edit-constraints'))).onPressed, isNull);
    expect(find.text('Choose this option'), findsNothing);
    expect(find.text('Plan acceptance is not available yet.'), findsOneWidget);
  });

  testWidgets('failed host callback shows safe retry requiring new confirmation', (tester) async {
    var calls = 0;
    await tester.pumpWidget(report(testSession(), onAccept: (_, _) async {
      calls++;
      throw StateError('private persistence detail');
    }));
    await tapKey(tester, 'accept-candidate');
    await tapKey(tester, 'confirm-accept');
    expect(find.byKey(const Key('handoff-failed')), findsOneWidget);
    expect(find.textContaining('private persistence detail'), findsNothing);
    await tapKey(tester, 'accept-candidate');
    expect(calls, 1);
    expect(find.byKey(const Key('confirm-accept')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('navigation injects host sessions and revisions without evaluating or writing schedules', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final schedule = DriftScheduleRepository(
      database,
      closeDatabaseOnDispose: false,
    );
    final analysis = DriftAnalysisRepository(
      database,
      closeDatabaseOnDispose: false,
    );
    addTearDown(schedule.close);
    addTearDown(analysis.close);
    addTearDown(database.close);
    final session = testSession();
    Widget app(int revision) => TaktApp(
        database: database,
        scheduleRepository: schedule,
        analysisRepository: analysis,
        decisionSession: session,
        currentInputRevision: revision,
        onAcceptCandidate: (_, _) async {});
    await tester.pumpWidget(app(3));
    await tester.pumpAndSettle();
    expect(find.text('Decision Report'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    final before = await schedule.loadState();
    await tester.pumpWidget(app(4));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stale-notice')), findsOneWidget);
    expect((await schedule.loadState()).commitments.length, before.commitments.length);
    final back = find.byTooltip('Back');
    await tester.ensureVisible(back);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.text('Decision Report'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

RevenueCatService _revenueCatService(_DecisionRevenueCatGateway gateway) {
  return RevenueCatService(
    config: RevenueCatConfig.validate(
      appEnv: 'test_store',
      apiKey: 'test_decision_report_public_key',
      buildMode: AppBuildMode.debug,
    ),
    gateway: gateway,
  );
}

Future<RevenueCatService> _initializedRevenueCat({
  required bool active,
  Object? customerInfoError,
}) async {
  final service = _revenueCatService(
    _DecisionRevenueCatGateway(
      active: active,
      customerInfoError: customerInfoError,
    ),
  );
  await service.initialize();
  return service;
}

final class _DecisionRevenueCatGateway implements RevenueCatGateway {
  _DecisionRevenueCatGateway({
    required this.active,
    this.customerInfoError,
    this.customerInfoFuture,
  });

  bool active;
  final Object? customerInfoError;
  final Future<RevenueCatCustomerSnapshot>? customerInfoFuture;

  @override
  Future<void> configure({required String apiKey}) async {}

  @override
  Future<RevenueCatCustomerSnapshot> getCustomerInfo() async {
    final future = customerInfoFuture;
    if (future != null) {
      return future;
    }
    final error = customerInfoError;
    if (error != null) {
      throw error;
    }
    return RevenueCatCustomerSnapshot(
      activeEntitlementIds: active ? const {'pro'} : const {},
    );
  }

  @override
  Future<RevenueCatPackageSnapshot?> getPackage({
    required String offeringIdentifier,
    required String packageIdentifier,
  }) async {
    return const RevenueCatPackageSnapshot(
      offeringIdentifier: 'default',
      packageIdentifier: r'$rc_lifetime',
      productIdentifier: 'takt_pro_lifetime_v1',
      priceString: r'$0.99',
    );
  }

  @override
  Future<RevenueCatCustomerSnapshot> purchasePackage({
    required String offeringIdentifier,
    required String packageIdentifier,
  }) async {
    active = true;
    return const RevenueCatCustomerSnapshot(
      activeEntitlementIds: {'pro'},
    );
  }

  @override
  Future<RevenueCatCustomerSnapshot> restorePurchases() async {
    return RevenueCatCustomerSnapshot(
      activeEntitlementIds: active ? const {'pro'} : const {},
    );
  }
}
