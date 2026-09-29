import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takt_mobile/data/database/app_database.dart';
import 'package:takt_mobile/data/repositories/drift_analysis_repository.dart';
import 'package:takt_mobile/data/repositories/drift_schedule_repository.dart';
import 'package:takt_mobile/main.dart';
import 'package:takt_mobile/models/decision_intent.dart';
import 'package:takt_mobile/models/enums.dart';
import 'package:takt_mobile/models/evaluation_session.dart';
import 'package:takt_mobile/screens/rekomendasi_jadwal_screen.dart';
import 'package:takt_mobile/theme/app_theme.dart';

import 'support/decision_fixture.dart';

Widget report(EvaluationSession? session, {int revision = 3,
    AcceptCandidateHandler? onAccept, ValueChanged<EditConstraintsIntent>? onEdit,
    ValueChanged<IgnoreRecommendationIntent>? onIgnore, double scale = 1}) => MaterialApp(
  theme: AppTheme.dark,
  home: Builder(builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: Scaffold(body: RekomendasiJadwalScreen(session: session,
        currentInputRevision: revision, onAccept: onAccept,
        onEditConstraints: onEdit, onIgnore: onIgnore)),
  )),
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
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(report(testSession(), scale: 1.5, onAccept: (_, _) async {}));
    expect(find.text('Readiness'), findsOneWidget);
    expect(find.text('Feasibility'), findsOneWidget);
    expect(find.text('Tight capacity'), findsOneWidget);
    expect(find.text('System primary recommendation'), findsOneWidget);
    expect(find.text('Suggested schedule · Not added to calendar'), findsWidgets);
    expect(find.text('Remaining buffer: 180 min'), findsOneWidget);
    expect(find.text('Remaining buffer: 120 min'), findsOneWidget);
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

  testWidgets('confirmation hands off the exact alternative/session once with no persistence claim', (tester) async {
    final session = testSession();
    final gate = Completer<void>();
    final calls = <(EvaluationSession, AcceptCandidateIntent)>[];
    await tester.pumpWidget(report(session, onAccept: (s, intent) {
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