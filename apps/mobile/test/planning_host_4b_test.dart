import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:provider/provider.dart';
import 'package:takt_mobile/data/database/app_database.dart';
import 'package:takt_mobile/main.dart';
import 'package:takt_mobile/data/remote/plan_api_client.dart';
import 'package:takt_mobile/data/repositories/drift_evaluation_repository.dart';
import 'package:takt_mobile/data/repositories/drift_saved_plan_repository.dart';
import 'package:takt_mobile/data/repositories/drift_schedule_repository.dart';
import 'package:takt_mobile/data/repositories/evaluation_repository.dart';
import 'package:takt_mobile/data/repositories/analysis_repository.dart';
import 'package:takt_mobile/data/repositories/schedule_repository.dart';
import 'package:takt_mobile/viewmodels/saved_plan_detail_view_model.dart';
import 'package:takt_mobile/screens/saved_plan_detail_screen.dart';
import 'package:takt_mobile/data/repositories/saved_plan_repository.dart';
import 'package:takt_mobile/models/active_accepted_block.dart';
import 'package:takt_mobile/models/analysis_snapshot.dart';
import 'package:takt_mobile/models/decision_intent.dart';
import 'package:takt_mobile/models/enums.dart';
import 'package:takt_mobile/models/evaluation.dart';
import 'package:takt_mobile/models/plan_evaluation_wire.dart';
import 'package:takt_mobile/models/planning_input_draft.dart';
import 'package:takt_mobile/models/reevaluation_wire.dart';
import 'package:takt_mobile/models/saved_plan.dart';
import 'package:takt_mobile/models/saved_plan_revision.dart';
import 'package:takt_mobile/screens/planning_setup_screen.dart';
import 'package:takt_mobile/viewmodels/planning_host_view_model.dart';

import 'support/decision_fixture.dart';

void main() {
  late AppDatabase db;
  late DriftEvaluationRepository evaluations;
  late DriftSavedPlanRepository savedPlans;
  late DriftScheduleRepository schedule;
  late AnalysisSnapshot snapshot;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    evaluations = DriftEvaluationRepository(db);
    savedPlans = DriftSavedPlanRepository(db);
    schedule = DriftScheduleRepository(db);
    await db.initialize();
    await schedule.initialize();
    snapshot = _snapshot();
    await _seedSnapshot(db, snapshot);
  });

  tearDown(() => db.close());

  test('persisted evaluation is reloaded before publishing session', () async {
    final api = _ControlledPlanApi();
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    host.addTask(_task());
    await host.evaluate();

    expect(api.evaluateCalls, 1);
    expect(host.phase, PlanningHostPhase.decision);
    expect(host.activeSession, isNotNull);
    final id = host.activeSession!.parsedResponse.evaluationId;
    final persisted = await evaluations.evaluationById(id);
    expect(persisted, isNotNull);
    expect(host.activeSession!.evaluationRequestJson, persisted!.requestJson);
    expect(host.activeSession!.evaluationResponseJson, persisted.responseJson);
    host.dispose();
  });

  test('leaveDecision clears only the active presentation session', () async {
    final api = _ControlledPlanApi();
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    host.addTask(_task());
    await host.evaluate();
    final evaluation = host.activeSession!.parsedResponse.evaluationId;

    expect(host.phase, PlanningHostPhase.decision);
    expect(host.activeSession, isNotNull);
    host.leaveDecision();

    expect(host.phase, PlanningHostPhase.setup);
    expect(host.activeSession, isNull);
    expect(host.savedPlan, isNull);
    expect(await evaluations.evaluationById(evaluation), isNotNull);
    host.dispose();
  });

  testWidgets('production Decision Report UI back exits host decision lifecycle',
      (tester) async {
    final api = _ControlledPlanApi();
    await tester.pumpWidget(TaktApp(database: db, planApiClient: api));
    await _pumpUi(tester);

    final rootContext = tester.element(find.byType(RootShell));
    final host = Provider.of<PlanningHostViewModel>(
      rootContext,
      listen: false,
    );
    await host.startPlanning(snapshot);
    host.addTask(_task());
    await host.evaluate();
    await _pumpUi(tester);

    await tester.tap(find.text('Analysis'));
    await _pumpUi(tester);
    expect(find.text('Decision Report'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await _pumpUi(tester);

    expect(find.text('Decision Report'), findsNothing);
    expect(host.phase, PlanningHostPhase.setup);
    expect(host.activeSession, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpUi(tester);
  });

  testWidgets('production Decision Report system back exits to analysis parent',
      (tester) async {
    final api = _ControlledPlanApi();
    await tester.pumpWidget(TaktApp(database: db, planApiClient: api));
    await _pumpUi(tester);

    final rootContext = tester.element(find.byType(RootShell));
    final host = Provider.of<PlanningHostViewModel>(
      rootContext,
      listen: false,
    );
    await host.startPlanning(snapshot);
    host.addTask(_task());
    await host.evaluate();
    await _pumpUi(tester);

    await tester.tap(find.text('Analysis'));
    await _pumpUi(tester);
    expect(find.text('Decision Report'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await _pumpUi(tester);

    expect(find.text('Decision Report'), findsNothing);
    expect(host.phase, PlanningHostPhase.setup);
    expect(host.activeSession, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpUi(tester);
  });

  testWidgets('Saved Plans uses neutral accepted state and system back returns to list',
      (tester) async {
    await _persistAndAcceptPrior(evaluations, savedPlans, snapshot);
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(TaktApp(database: db));
    await _pumpUi(tester);

    await tester.tap(find.text('Plans'));
    await _pumpUi(tester);
    expect(find.text('Saved Plans'), findsOneWidget);
    expect(find.text('ACCEPTED'), findsOneWidget);
    expect(find.text('CURRENT'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Open plan'));
    await tester.tap(find.text('Open plan'));
    await _pumpUi(tester);
    expect(find.text('Saved Plan'), findsOneWidget);
    expect(find.text('ACCEPTED'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.handlePopRoute();
    await _pumpUi(tester);
    expect(find.text('Saved Plans'), findsOneWidget);
    expect(find.text('Saved Plan'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpUi(tester);
  });

  test('late HTTP response is dropped after input revision changes', () async {
    final api = _ControlledPlanApi(delayed: true);
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    host.addTask(_task());
    final future = host.evaluate();
    await _waitFor(() => api.lastEvaluationRequest != null);

    host.replaceReadiness(
      const ReadinessContextDraft(age: 21),
    );
    api.completeEvaluate();
    await future;

    expect(host.activeSession, isNull);
    expect(
      await evaluations.evaluationById(evaluationId),
      isNull,
    );
    host.dispose();
  });

  test('startPlanning replacement invalidates an in-flight prior lifecycle',
      () async {
    final api = _ControlledPlanApi(delayed: true);
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );
    final secondSnapshot = _snapshotFor(
      id: 'snapshot-b',
      competitionId: 'competition-b',
    );
    await _seedSnapshot(db, secondSnapshot);

    await host.startPlanning(snapshot);
    host.addTask(_task());
    final firstEvaluation = host.evaluate();
    await _waitFor(() => api.lastEvaluationRequest != null);

    await host.startPlanning(secondSnapshot);
    expect(host.phase, PlanningHostPhase.setup);
    expect(host.analysisSnapshot?.id, secondSnapshot.id);
    expect(host.draft, isNotNull);

    api.completeEvaluate();
    await firstEvaluation;

    expect(host.phase, PlanningHostPhase.setup);
    expect(host.analysisSnapshot?.id, secondSnapshot.id);
    expect(host.activeSession, isNull);
    expect(await evaluations.evaluationById(evaluationId), isNull);
    host.dispose();
  });

  testWidgets('Planning task save with a focused field does not crash',
      (tester) async {
    final host = PlanningHostViewModel(
      apiClient: _ControlledPlanApi(),
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );
    await host.startPlanning(snapshot);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlanningSetupScreen(host: host),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Add task'));
    await tester.tap(find.text('Add task'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    final taskNameField = find
        .descendant(of: dialog, matching: find.byType(TextField))
        .first;
    await tester.tap(taskNameField);
    await tester.enterText(taskNameField, 'Build prototype');

    await tester.tap(find.text('Save task'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Build prototype'), findsOneWidget);
    host.dispose();
  });

  testWidgets('Planning Setup freezes authoritative fields while request is active',
      (tester) async {
    final api = _ControlledPlanApi(delayed: true);
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );
    await host.startPlanning(snapshot);
    host.addTask(_task());

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: host,
          builder: (context, _) => Scaffold(
            body: PlanningSetupScreen(host: host),
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Evaluate'));
    await tester.pump();
    await tester.tap(find.text('Evaluate'));
    await tester.pump();
    for (var i = 0; i < 20 && api.lastEvaluationRequest == null; i++) {
      await tester.pump();
    }
    expect(api.lastEvaluationRequest, isNotNull);

    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields, isNotEmpty);
    expect(fields.every((field) => field.enabled == false), isTrue);

    api.completeEvaluate();
    await tester.pumpAndSettle();
    host.dispose();
  });

  testWidgets('Planning Setup stays frozen while a result awaits Retry Save',
      (tester) async {
    final api = _ControlledPlanApi();
    final failOnce = _FailOnceEvaluationRepository(evaluations);
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: failOnce,
      savedPlanRepository: savedPlans,
    );
    await host.startPlanning(snapshot);
    host.addTask(_task());

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: host,
          builder: (context, _) => Scaffold(
            body: PlanningSetupScreen(host: host),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Evaluate'));
    await tester.pump();
    await tester.tap(find.text('Evaluate'));
    await tester.pumpAndSettle();

    expect(host.phase, PlanningHostPhase.persistenceError);
    expect(find.text('Retry local save'), findsOneWidget);
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields, isNotEmpty);
    expect(fields.every((field) => field.enabled == false), isTrue);
    host.dispose();
  });

  test('Retry Save persists without issuing a second HTTP request', () async {
    final api = _ControlledPlanApi();
    final failOnce = _FailOnceEvaluationRepository(evaluations);
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: failOnce,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    host.addTask(_task());
    await host.evaluate();

    expect(host.phase, PlanningHostPhase.persistenceError);
    expect(host.activeSession, isNull);
    expect(api.evaluateCalls, 1);

    await host.retryPersistence();

    expect(api.evaluateCalls, 1);
    expect(host.phase, PlanningHostPhase.decision);
    expect(host.activeSession, isNotNull);
    expect(
      await evaluations.evaluationById(evaluationId),
      isNotNull,
    );
    host.dispose();
  });

  test('discardable evaluation persistence can be abandoned without HTTP retry',
      () async {
    final api = _ControlledPlanApi();
    final failOnce = _FailOnceEvaluationRepository(evaluations);
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: failOnce,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    host.addTask(_task());
    await host.evaluate();

    expect(host.phase, PlanningHostPhase.persistenceError);
    expect(host.canDiscardPendingResult, isTrue);
    expect(api.evaluateCalls, 1);

    host.discardPendingResult();

    expect(host.phase, PlanningHostPhase.setup);
    expect(host.canRetryPersistence, isFalse);
    expect(api.evaluateCalls, 1);
    expect(await evaluations.evaluationById(evaluationId), isNull);
    host.dispose();
  });

  test('trusted SUPERSEDED witness cannot be discarded before local save',
      () async {
    final prior = await _persistAndAcceptPrior(
      evaluations,
      savedPlans,
      snapshot,
    );
    final failOnce = _FailOnceReevaluationRepository(evaluations);
    final api = _ReevaluationPlanApi(
      mode: _ReevaluationMode.failure,
      priorEvaluationId: prior.id,
      priorBasisFingerprint: prior.evaluationBasisFingerprint,
    );
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: failOnce,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    await host.evaluate();

    expect(host.phase, PlanningHostPhase.persistenceError);
    expect(host.hasKnownUnpersistedStaleWitness, isTrue);
    expect(host.canDiscardPendingResult, isFalse);
    expect(api.reevaluateCalls, 1);
    expect(await evaluations.isStale(prior.id), isFalse);

    host.discardPendingResult();
    expect(host.phase, PlanningHostPhase.persistenceError);
    expect(host.hasKnownUnpersistedStaleWitness, isTrue);

    await host.retryPersistence();

    expect(api.reevaluateCalls, 1);
    expect(await evaluations.isStale(prior.id), isTrue);
    expect(host.phase, PlanningHostPhase.error);
    final plan = await savedPlans.planForCompetition(snapshot.competitionId);
    final detail = await savedPlans.loadDetail(plan!.id);
    expect(detail!.summary.stale, isTrue);
    expect(detail.revisions, hasLength(1));
    host.dispose();
  });

  test('SUPERSEDED success persistence is correctness-bearing and non-discardable',
      () async {
    final prior = await _persistAndAcceptPrior(
      evaluations,
      savedPlans,
      snapshot,
    );
    final failOnce = _FailOnceReevaluationRepository(evaluations);
    final api = _ReevaluationPlanApi(
      mode: _ReevaluationMode.superseded,
      priorEvaluationId: prior.id,
      priorBasisFingerprint: prior.evaluationBasisFingerprint,
    );
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: failOnce,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    await host.evaluate();

    expect(host.phase, PlanningHostPhase.persistenceError);
    expect(host.hasKnownUnpersistedStaleWitness, isTrue);
    expect(host.canDiscardPendingResult, isFalse);
    expect(api.reevaluateCalls, 1);
    expect(await evaluations.isStale(prior.id), isFalse);

    await host.retryPersistence();

    expect(api.reevaluateCalls, 1);
    expect(await evaluations.isStale(prior.id), isTrue);
    expect(host.phase, PlanningHostPhase.decision);
    expect(host.activeSession, isNotNull);
    host.dispose();
  });

  test('abandoned planning request ignores its late response', () async {
    final api = _ControlledPlanApi(delayed: true);
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    host.addTask(_task());
    final evaluation = host.evaluate();
    await Future<void>.delayed(Duration.zero);

    expect(host.phase, PlanningHostPhase.requesting);
    expect(host.abandonRequest(), isTrue);
    expect(host.phase, PlanningHostPhase.setup);

    api.completeEvaluate();
    await evaluation;

    expect(host.phase, PlanningHostPhase.setup);
    expect(host.activeSession, isNull);
    expect(await evaluations.evaluationById(evaluationId), isNull);
    host.dispose();
  });

  test('unexpected request exception unlocks setup with retry available',
      () async {
    final api = _RawFailurePlanApi();
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    host.addTask(_task());
    await host.evaluate();

    expect(host.phase, PlanningHostPhase.error);
    expect(host.busy, isFalse);
    expect(host.inputsLocked, isFalse);
    expect(host.failure?.code, 'CLIENT_RUNTIME_ERROR');
    expect(host.canRetryRequest, isTrue);
    host.dispose();
  });

  test('planning request retry reuses the exact assembled request', () async {
    final api = _FailOncePlanApi();
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    host.addTask(_task());
    await host.evaluate();

    expect(host.phase, PlanningHostPhase.error);
    expect(host.canRetryRequest, isTrue);
    expect(api.evaluateCalls, 1);
    final firstRequest = api.requests.single;

    await host.retryRequest();

    expect(api.evaluateCalls, 2);
    expect(api.requests, [firstRequest, firstRequest]);
    expect(host.phase, PlanningHostPhase.decision);
    host.dispose();
  });

  test('failed acceptance save can retry without a second backend evaluation',
      () async {
    final api = _ControlledPlanApi();
    final failAccept = _FailOnceSavedPlanRepository(savedPlans);
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: failAccept,
    );

    await host.startPlanning(snapshot);
    host.addTask(_task());
    await host.evaluate();
    final session = host.activeSession!;
    final intent = AcceptCandidateIntent(
      sessionId: session.sessionId,
      evaluationId: session.parsedResponse.evaluationId,
      candidateId: primaryId,
      selectionSource: SelectionSource.primary,
    );

    await expectLater(
      host.accept(session, intent),
      throwsA(isA<AcceptancePersistenceExceptionProxy>()),
    );

    expect(host.phase, PlanningHostPhase.decision);
    expect(host.hasPendingAcceptance, isTrue);
    expect(host.canRetryAcceptancePersistence, isTrue);
    expect(api.evaluateCalls, 1);
    expect(
      await savedPlans.planForCompetition(snapshot.competitionId),
      isNull,
    );

    await host.retryAcceptancePersistence();

    expect(api.evaluateCalls, 1);
    expect(host.phase, PlanningHostPhase.accepted);
    expect(host.hasPendingAcceptance, isFalse);
    final plan = await savedPlans.planForCompetition(snapshot.competitionId);
    final detail = await savedPlans.loadDetail(plan!.id);
    expect(detail!.revisions, hasLength(1));
    expect(detail.acceptedCommitments, hasLength(1));
    host.dispose();
  });

  test('cancelling pending acceptance clears intent without Ignore or deletion',
      () async {
    final api = _ControlledPlanApi();
    final failAccept = _FailOnceSavedPlanRepository(savedPlans);
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: failAccept,
    );

    await host.startPlanning(snapshot);
    host.addTask(_task());
    await host.evaluate();
    final session = host.activeSession!;
    final intent = AcceptCandidateIntent(
      sessionId: session.sessionId,
      evaluationId: session.parsedResponse.evaluationId,
      candidateId: primaryId,
      selectionSource: SelectionSource.primary,
    );

    await expectLater(
      host.accept(session, intent),
      throwsA(isA<AcceptancePersistenceExceptionProxy>()),
    );
    expect(host.hasPendingAcceptance, isTrue);

    host.cancelPendingAcceptance();

    expect(host.phase, PlanningHostPhase.decision);
    expect(host.hasPendingAcceptance, isFalse);
    expect(host.activeSession, same(session));
    expect(api.evaluateCalls, 1);
    expect(
      await savedPlans.planForCompetition(snapshot.competitionId),
      isNull,
    );
    host.dispose();
  });

  test('re-evaluate draft seeds semantic values from prior evaluation', () async {
    final prior = await evaluations.persistEvaluation(
      analysisSnapshot: snapshot,
      evaluationRequestJson: _priorRequest(),
      evaluationResponseJson: jsonEncode(decisionFixture()),
      planningWindowPolicyJson: jsonEncode({
        'policy_version': 'planning-window-policy-v1',
        'timezone': 'Asia/Jakarta',
        'start_local': '09:00',
        'end_local': '20:00',
      }),
    );
    await savedPlans.acceptEvaluation(
      evaluationId: prior.id,
      candidateId: primaryId,
      selectionSource: SelectionSource.primary,
    );

    // Global defaults deliberately diverge from the accepted evaluation.
    await schedule.savePlanningPreferences(
      (await schedule.loadState()).preferences.copyWith(
        maxProjectMinutesPerDay: 30,
        preferredFocusMinutes: 15,
        bufferTargetMinutes: 0,
        updatedAtEpochMs: 2,
      ),
    );

    final host = PlanningHostViewModel(
      apiClient: _ControlledPlanApi(),
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );
    await host.startPlanning(snapshot);

    final draft = host.draft!;
    expect(host.hasAcceptedPlan, isTrue);
    expect(draft.readinessContext.age, 21);
    expect(draft.readinessContext.studentStatus, isTrue);
    expect(draft.readinessContext.country, 'ID');
    expect(draft.preferences.maxProjectMinutesPerDay, 300);
    expect(draft.preferences.preferredFocusMinutes, 100);
    expect(draft.preferences.bufferTargetMinutes, 45);
    expect(draft.windowPolicy.startLocal, '09:00');
    expect(draft.windowPolicy.endLocal, '20:00');
    expect(draft.tasks.single.taskId, 'task-draft');
    host.dispose();
  });

  test('UNCHANGED re-evaluation keeps accepted revision current', () async {
    final prior = await _persistAndAcceptPrior(
      evaluations,
      savedPlans,
      snapshot,
    );
    final api = _ReevaluationPlanApi(
      mode: _ReevaluationMode.unchanged,
      priorEvaluationId: prior.id,
      priorBasisFingerprint: prior.evaluationBasisFingerprint,
    );
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    await host.evaluate();

    expect(api.reevaluateCalls, 1);
    expect(host.phase, PlanningHostPhase.unchanged);
    expect(host.activeSession, isNull);
    expect(await evaluations.isStale(prior.id), isFalse);
    final plan = await savedPlans.planForCompetition(snapshot.competitionId);
    final detail = await savedPlans.loadDetail(plan!.id);
    expect(detail!.revisions, hasLength(1));
    expect(detail.summary.currentRevision.evaluationId, prior.id);
    host.dispose();
  });

  test('Accept remains successful when post-commit Evaluation reload fails',
      () async {
    final api = _ControlledPlanApi();
    final reloadFailure = _ToggleReadEvaluationRepository(evaluations);
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: reloadFailure,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    host.addTask(_task());
    await host.evaluate();
    final session = host.activeSession!;
    reloadFailure.failReads = true;

    await host.accept(
      session,
      AcceptCandidateIntent(
        sessionId: session.sessionId,
        evaluationId: session.parsedResponse.evaluationId,
        candidateId: primaryId,
        selectionSource: SelectionSource.primary,
      ),
    );

    expect(host.phase, PlanningHostPhase.accepted);
    final plan = await savedPlans.planForCompetition(snapshot.competitionId);
    expect(plan, isNotNull);
    final detail = await savedPlans.loadDetail(plan!.id);
    expect(detail!.summary.currentRevision.evaluationId, evaluationId);
    host.dispose();
  });

  test('SUPERSEDED re-evaluation publishes fresh session and Accept creates revision 2',
      () async {
    final prior = await _persistAndAcceptPrior(
      evaluations,
      savedPlans,
      snapshot,
    );
    final api = _ReevaluationPlanApi(
      mode: _ReevaluationMode.superseded,
      priorEvaluationId: prior.id,
      priorBasisFingerprint: prior.evaluationBasisFingerprint,
    );
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    await host.evaluate();

    expect(host.phase, PlanningHostPhase.decision);
    expect(await evaluations.isStale(prior.id), isTrue);
    final session = host.activeSession!;
    expect(session.parsedResponse.evaluationId, _freshEvaluationId);

    await host.accept(
      session,
      AcceptCandidateIntent(
        sessionId: session.sessionId,
        evaluationId: session.parsedResponse.evaluationId,
        candidateId: primaryId,
        selectionSource: SelectionSource.primary,
      ),
    );

    expect(host.phase, PlanningHostPhase.accepted);
    final plan = await savedPlans.planForCompetition(snapshot.competitionId);
    final detail = await savedPlans.loadDetail(plan!.id);
    expect(detail!.revisions, hasLength(2));
    expect(detail.summary.currentRevision.revisionNumber, 2);
    expect(detail.summary.currentRevision.evaluationId, _freshEvaluationId);
    expect(detail.summary.stale, isFalse);
    host.dispose();
  });

  test('trusted SUPERSEDED failure marks prior stale and keeps old schedule active',
      () async {
    final prior = await _persistAndAcceptPrior(
      evaluations,
      savedPlans,
      snapshot,
    );
    final api = _ReevaluationPlanApi(
      mode: _ReevaluationMode.failure,
      priorEvaluationId: prior.id,
      priorBasisFingerprint: prior.evaluationBasisFingerprint,
    );
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    await host.evaluate();

    expect(host.phase, PlanningHostPhase.error);
    expect(host.failure?.code, 'PLANNING_EXECUTION_FAILED');
    expect(await evaluations.isStale(prior.id), isTrue);
    final active = await savedPlans.activeAcceptedBlocks();
    expect(active, hasLength(1));
    final plan = await savedPlans.planForCompetition(snapshot.competitionId);
    final detail = await savedPlans.loadDetail(plan!.id);
    expect(detail!.revisions, hasLength(1));
    expect(detail.summary.stale, isTrue);
    host.dispose();
  });

  test('unsupported re-evaluation contract cannot create a fresh baseline', () async {
    final prior = await _persistAndAcceptPrior(
      evaluations,
      savedPlans,
      snapshot,
    );
    final api = _ReevaluationPlanApi(
      mode: _ReevaluationMode.unsupported,
      priorEvaluationId: prior.id,
      priorBasisFingerprint: prior.evaluationBasisFingerprint,
    );
    final host = PlanningHostViewModel(
      apiClient: api,
      scheduleRepository: schedule,
      evaluationRepository: evaluations,
      savedPlanRepository: savedPlans,
    );

    await host.startPlanning(snapshot);
    await host.evaluate();

    expect(host.phase, PlanningHostPhase.error);
    expect(host.canEvaluate, isFalse);
    expect(host.canRetryRequest, isFalse);
    expect(host.canReloadContext, isFalse);
    host.commitDraft(host.draft!);
    await host.evaluate();
    expect(api.evaluateCalls, 0);
    expect(api.reevaluateCalls, 1);
    expect(host.phase, PlanningHostPhase.error);
    expect(await evaluations.isStale(prior.id), isFalse);
    host.dispose();
  });

  for (final code in [
    'UNKNOWN_BACKEND_ERROR', 'EVALUATION_INVARIANT_FAILED',
    'PLANNING_EXECUTION_FAILED', 'REEVALUATION_CONTEXT_INVALID',
    'UNSUPPORTED_REEVALUATION_CONTRACT',
  ]) {
    test('$code cannot bypass policy via Evaluate or unchanged/changed draft', () async {
      final api = _FailOncePlanApi(code: code);
      final host = PlanningHostViewModel(apiClient: api,
          scheduleRepository: schedule, evaluationRepository: evaluations,
          savedPlanRepository: savedPlans);
      await host.startPlanning(snapshot);
      host.addTask(_task());
      await host.evaluate();
      final revision = host.inputRevision;
      host.commitDraft(host.draft!);
      host.updateTask(_task().copyWith(name: 'Changed task'));
      await host.evaluate();
      await host.retryRequest();
      expect(api.evaluateCalls, 1);
      expect(host.failure?.code, code);
      expect(host.inputRevision, revision);
      expect(host.canEvaluate, isFalse);
      if (code == 'REEVALUATION_CONTEXT_INVALID') {
        expect(host.canReloadContext, isTrue);
        await host.reloadContext();
        expect(host.phase, PlanningHostPhase.setup);
        expect(api.evaluateCalls, 1);
      }
      host.dispose();
    });
  }

  for (final code in ['SOLVER_INDETERMINATE', 'PLANNING_INPUT_INVALID']) {
    test('$code requires a semantic input edit before Evaluate', () async {
      final api = _FailOncePlanApi(code: code);
      final host = PlanningHostViewModel(apiClient: api,
          scheduleRepository: schedule, evaluationRepository: evaluations,
          savedPlanRepository: savedPlans);
      await host.startPlanning(snapshot);
      host.addTask(_task());
      await host.evaluate();
      final draft = host.draft!;
      final revision = host.inputRevision;
      host.commitDraft(draft.copyWith(preferences: draft.preferences.copyWith(
        updatedAtEpochMs: draft.preferences.updatedAtEpochMs + 1,
      )));
      await host.evaluate();
      expect(host.inputRevision, revision);
      expect(api.evaluateCalls, 1);
      host.updateTask(_task().copyWith(effortMaxMinutes: 200));
      await host.evaluate();
      expect(api.evaluateCalls, 2);
      expect(host.phase, PlanningHostPhase.decision);
      host.dispose();
    });
  }

  for (final saveFailsFirst in [false, true]) {
    test('durable fresh result reload failure cannot save/discard again ($saveFailsFirst)', () async {
      final api = _ControlledPlanApi();
      final repo = _ToggleReadEvaluationRepository(
        saveFailsFirst ? _FailOnceEvaluationRepository(evaluations) : evaluations,
      )..failReads = true;
      final host = PlanningHostViewModel(apiClient: api,
          scheduleRepository: schedule, evaluationRepository: repo,
          savedPlanRepository: savedPlans);
      await host.startPlanning(snapshot);
      host.addTask(_task());
      await host.evaluate();
      if (saveFailsFirst) {
        expect(host.canDiscardPendingResult, isTrue);
        await host.retryPersistence();
      }
      expect(host.phase, PlanningHostPhase.publicationError);
      expect(host.failure?.code, 'LOCAL_PUBLICATION_FAILED');
      expect(host.canRetryPersistence, isFalse);
      expect(host.canDiscardPendingResult, isFalse);
      expect(await evaluations.evaluationById(evaluationId), isNotNull);
      final writes = repo.writes;
      host.discardPendingResult();
      await host.retryPersistence();
      await host.evaluate();
      await host.startPlanning(snapshot);
      await host.retryPublication();
      expect(host.phase, PlanningHostPhase.publicationError);
      expect(repo.writes, writes);
      repo.failReads = false;
      await host.retryPublication();
      expect(host.phase, PlanningHostPhase.decision);
      expect(repo.writes, writes);
      expect(api.evaluateCalls, 1);
      host.dispose();
    });
  }

  for (final mode in [_ReevaluationMode.failure, _ReevaluationMode.superseded, _ReevaluationMode.unchanged]) {
    test('committed re-evaluation $mode retries refresh, never transaction/request', () async {
      final prior = await _persistAndAcceptPrior(evaluations, savedPlans, snapshot);
      final repo = _FailOnceSavedPlanRepository(savedPlans, failAccept: false);
      final api = _ReevaluationPlanApi(mode: mode, priorEvaluationId: prior.id,
          priorBasisFingerprint: prior.evaluationBasisFingerprint);
      final counted = _ToggleReadEvaluationRepository(evaluations);
      final host = PlanningHostViewModel(apiClient: api,
          scheduleRepository: schedule, evaluationRepository: counted,
          savedPlanRepository: repo);
      await host.startPlanning(snapshot);
      repo.failRefresh = true;
      await host.evaluate();
      expect(host.phase, PlanningHostPhase.publicationError);
      expect(host.canRetryPersistence, isFalse);
      expect(host.canDiscardPendingResult, isFalse);
      final before = await db.customSelect('SELECT * FROM reevaluation_transitions').get();
      expect(before, hasLength(1));
      await host.retryPersistence();
      await host.retryPublication();
      repo.failRefresh = false;
      await host.retryPublication();
      expect(host.phase, mode == _ReevaluationMode.failure ? PlanningHostPhase.error
          : mode == _ReevaluationMode.unchanged ? PlanningHostPhase.unchanged
          : PlanningHostPhase.decision);
      expect(api.reevaluateCalls, 1);
      expect(counted.reevaluationWrites, 1);
      expect(await db.customSelect('SELECT * FROM reevaluation_transitions').get(), hasLength(1));
      expect(await evaluations.isStale(prior.id), mode != _ReevaluationMode.unchanged);
      host.dispose();
    });
  }

  test('local planning reads are sanitized and require context reload', () async {
    final api = _ControlledPlanApi();
    final repo = _FailingScheduleReads(schedule);
    final host = PlanningHostViewModel(apiClient: api,
        scheduleRepository: repo, evaluationRepository: evaluations,
        savedPlanRepository: savedPlans);
    repo.failReads = true;
    await host.startPlanning(snapshot);
    expect(host.failure?.code, 'LOCAL_CONTEXT_READ_FAILED');
    expect(host.failure?.message, isNot(contains('private sqlite')));
    repo.failReads = false;
    await host.reloadContext();
    expect(host.phase, PlanningHostPhase.setup);
    host.addTask(_task());
    repo.failReads = true;
    await host.evaluate();
    expect(host.failure?.code, 'LOCAL_CONTEXT_READ_FAILED');
    expect(api.evaluateCalls, 0);
    repo.failReads = false;
    await host.reloadContext();
    repo.failReads = true;
    await host.useCurrentDefaults();
    expect(host.failure?.code, 'LOCAL_CONTEXT_READ_FAILED');
    expect(host.failure?.message, isNot(contains('private sqlite')));
    host.dispose();
  });

  for (final failRefresh in [false, true]) {
    test('progress commit followed by ${failRefresh ? "refresh" : "detail"} failure is durable', () async {
      await _persistAndAcceptPrior(evaluations, savedPlans, snapshot);
      final plan = (await savedPlans.planForCompetition(snapshot.competitionId))!;
      final repo = _FailOnceSavedPlanRepository(savedPlans, failAccept: false);
      final vm = SavedPlanDetailViewModel(repo);
      await vm.load(plan.id);
      final taskId = vm.detail!.tasks.single.task.id;
      repo.failRefresh = failRefresh;
      repo.failDetail = !failRefresh;
      expect(await vm.updateProgress(savedPlanTaskId: taskId, progressPercent: 65), isTrue);
      expect(vm.errorCode, 'LOCAL_REFRESH_FAILED');
      expect(vm.error, contains('is saved'));
      expect(vm.error, isNot(contains('private sqlite')));
      expect((await savedPlans.loadDetail(plan.id))!.tasks.single.progress.progressPercent, 65);
      repo.failRefresh = false;
      repo.failDetail = false;
      await vm.load(plan.id);
      expect(vm.detail!.tasks.single.progress.progressPercent, 65);
      expect(repo.progressWrites, 1);
      expect(vm.error, isNull);
      vm.dispose();
    });
  }

  for (final scenario in ['unsaved', 'publication', 'retry', 'blocked', 'reload', 'stale']) {
    testWidgets('Planning recovery $scenario works at 320px and 2x text', (tester) async {
      _compactViewport(tester);
      final PlanApiClient api;
      final EvaluationRepository repo;
      if (scenario == 'stale') {
        final prior = await _persistAndAcceptPrior(evaluations, savedPlans, snapshot);
        api = _ReevaluationPlanApi(mode: _ReevaluationMode.failure,
            priorEvaluationId: prior.id, priorBasisFingerprint: prior.evaluationBasisFingerprint);
        repo = _FailOnceReevaluationRepository(evaluations);
      } else {
        api = switch (scenario) {
          'blocked' => _FailOncePlanApi(code: 'UNKNOWN_BACKEND_ERROR'),
          'reload' => _FailOncePlanApi(code: 'REEVALUATION_CONTEXT_INVALID'),
          'retry' => _FailOncePlanApi(),
          _ => _ControlledPlanApi(),
        };
        repo = switch (scenario) {
          'unsaved' => _FailOnceEvaluationRepository(evaluations),
          'publication' => _ToggleReadEvaluationRepository(evaluations)..failReads = true,
          _ => evaluations,
        };
      }
      final host = PlanningHostViewModel(apiClient: api,
          scheduleRepository: schedule, evaluationRepository: repo,
          savedPlanRepository: savedPlans);
      await host.startPlanning(snapshot);
      if (scenario != 'stale') host.addTask(_task());
      await host.evaluate();
      await tester.pumpWidget(MaterialApp(home: AnimatedBuilder(
        animation: host, builder: (context, _) => Scaffold(
          body: PlanningSetupScreen(host: host),
        ),
      )));
      await _pumpUi(tester);
      expect(find.byKey(const Key('recovery-panel')), findsOneWidget);
      final label = switch (scenario) {
        'unsaved' || 'stale' => 'Retry local save',
        'publication' => 'Retry reload',
        'retry' => 'Retry request',
        'reload' => 'Reload context',
        _ => null,
      };
      if (label != null) {
        final button = find.text(label);
        await _showRecoveryControl(tester, button);
        expect(button.hitTestable(), findsOneWidget);
        if (repo is _ToggleReadEvaluationRepository) repo.failReads = false;
        await tester.tap(button);
        await _pumpUi(tester);
        expect(host.canRetryPersistence, isFalse);
        expect(host.canRetryPublication, isFalse);
      } else {
        expect(find.text('Evaluate'), findsNothing);
        expect(find.text('Re-evaluate plan'), findsNothing);
        expect(find.text('Retry request'), findsNothing);
      }
      final exception = tester.takeException();
      expect(exception, isNull,
          reason: exception is FlutterError ? exception.toStringDeep() : null);
      await tester.pumpWidget(const SizedBox.shrink());
      host.dispose();
    });
  }

  testWidgets('Saved Plan local read failure is caught by actual Re-evaluate at 320px/2x', (tester) async {
    _compactViewport(tester);
    await _persistAndAcceptPrior(evaluations, savedPlans, snapshot);
    final analysis = _ThrowingAnalysisRead();
    final api = _ControlledPlanApi();
    await tester.pumpWidget(TaktApp(database: db, analysisRepository: analysis, planApiClient: api));
    await _pumpUi(tester);
    await tester.tap(find.text('Plans'));
    await _pumpUi(tester);
    await _showRecoveryControl(tester, find.text('Open plan'));
    await tester.tap(find.text('Open plan'));
    await _pumpUi(tester);
    await _showRecoveryControl(tester, find.text('Re-evaluate'));
    await tester.tap(find.text('Re-evaluate'));
    await _pumpUi(tester);
    expect(find.byKey(const Key('recovery-panel')), findsOneWidget);
    expect(find.textContaining('private sqlite'), findsNothing);
    expect(analysis.reads, 1);
    await _showRecoveryControl(tester, find.text('Retry load context'));
    await tester.tap(find.text('Retry load context'));
    await _pumpUi(tester);
    expect(analysis.reads, 2);
    expect(api.evaluateCalls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpUi(tester);
  });

  testWidgets('Saved Plan refresh after durable progress is reachable at 320px/2x', (tester) async {
    _compactViewport(tester);
    await _persistAndAcceptPrior(evaluations, savedPlans, snapshot);
    final plan = (await savedPlans.planForCompetition(snapshot.competitionId))!;
    final repo = _FailOnceSavedPlanRepository(savedPlans, failAccept: false);
    final vm = SavedPlanDetailViewModel(repo);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SavedPlanDetailScreen(
      savedPlanId: plan.id, viewModel: vm,
    ))));
    await _pumpUi(tester);
    repo.failDetail = true;
    await vm.updateProgress(savedPlanTaskId: vm.detail!.tasks.single.task.id, progressPercent: 65);
    await _pumpUi(tester);
    expect(vm.errorCode, 'LOCAL_REFRESH_FAILED');
    await _showRecoveryControl(tester, find.text('Progress saved; display needs refresh'));
    expect(find.text('Progress saved; display needs refresh'), findsOneWidget);
    repo.failDetail = false;
    await _showRecoveryControl(tester, find.text('Retry refresh'));
    await tester.tap(find.text('Retry refresh'));
    await _pumpUi(tester);
    expect(vm.detail!.tasks.single.progress.progressPercent, 65);
    expect(repo.progressWrites, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    vm.dispose();
  });

}

enum _ReevaluationMode { unchanged, superseded, failure, unsupported }

const _freshEvaluationId = '22222222-2222-4222-8222-222222222222';
const _fallbackEvaluationId = '33333333-3333-4333-8333-333333333333';

final class _ReevaluationPlanApi implements PlanApiClient {
  _ReevaluationPlanApi({
    required this.mode,
    required this.priorEvaluationId,
    required this.priorBasisFingerprint,
  });

  final _ReevaluationMode mode;
  final String priorEvaluationId;
  final String priorBasisFingerprint;
  int evaluateCalls = 0;
  int reevaluateCalls = 0;

  @override
  Future<PlanEvaluateTransportResult> evaluate({
    required String evaluationRequestJson,
  }) async {
    evaluateCalls++;
    final raw = _decisionResponse(
      evaluationIdValue: _fallbackEvaluationId,
      basisFingerprint: List.filled(64, 'e').join(),
    );
    return PlanEvaluateTransportResult(
      evaluationRequestJson: evaluationRequestJson,
      evaluationResponseJson: raw,
      response: PlanEvaluateResponseV1.parse(raw),
    );
  }

  @override
  Future<PlanReevaluateTransportResult> reevaluate({
    required String priorEvaluationId,
    required String priorEvaluationResponseJson,
    required String currentEvaluationRequestJson,
  }) async {
    reevaluateCalls++;
    expect(priorEvaluationId, this.priorEvaluationId);
    expect(
      PlanEvaluateResponseV1.parse(priorEvaluationResponseJson).basis.fingerprint,
      priorBasisFingerprint,
    );

    if (mode == _ReevaluationMode.unsupported) {
      throw const PlanApiFailure(
        code: 'UNSUPPORTED_REEVALUATION_CONTRACT',
        stage: 'reevaluation',
        message: 'Prior evaluation basis structural version is not supported.',
        retryable: false,
      );
    }

    if (mode == _ReevaluationMode.failure) {
      final transition = ReevaluationTransitionWire.fromValue({
        'kind': 'SUPERSEDED',
        'prior_evaluation_id': this.priorEvaluationId,
        'prior_basis_fingerprint': priorBasisFingerprint,
        'current_basis_fingerprint': List.filled(64, 'c').join(),
        'prior_evaluation_freshness': 'STALE',
        'change_reasons': ['PLANNING_BASIS_CHANGED'],
      });
      final errorJson = jsonEncode({
        'code': 'PLANNING_EXECUTION_FAILED',
        'message': 'The planning pipeline could not complete execution.',
        'stage': 'planning',
        'details': <Object?>[],
      });
      throw PlanApiFailure(
        code: 'PLANNING_EXECUTION_FAILED',
        stage: 'planning',
        message: 'The planning pipeline could not complete execution.',
        retryable: true,
        statusCode: 500,
        transportRequestJson: _transportRequest(currentEvaluationRequestJson),
        transportResponseJson: jsonEncode({
          'error': jsonDecode(errorJson),
          'transition': transition.toJson(),
        }),
        transition: transition,
        errorJson: errorJson,
      );
    }

    if (mode == _ReevaluationMode.unchanged) {
      final transition = ReevaluationTransitionWire.fromValue({
        'kind': 'UNCHANGED',
        'prior_evaluation_id': this.priorEvaluationId,
        'prior_basis_fingerprint': priorBasisFingerprint,
        'current_basis_fingerprint': priorBasisFingerprint,
        'prior_evaluation_freshness': 'CURRENT',
        'change_reasons': <String>[],
      });
      final raw = jsonEncode({
        'transition': transition.toJson(),
        'evaluation': null,
      });
      return PlanReevaluateTransportResult(
        transportRequestJson: _transportRequest(currentEvaluationRequestJson),
        transportResponseJson: raw,
        evaluationRequestJson: currentEvaluationRequestJson,
        success: PlanReevaluateSuccessWire.parse(raw),
      );
    }

    final freshFingerprint = List.filled(64, 'd').join();
    final freshRaw = _decisionResponse(
      evaluationIdValue: _freshEvaluationId,
      basisFingerprint: freshFingerprint,
    );
    final transition = ReevaluationTransitionWire.fromValue({
      'kind': 'SUPERSEDED',
      'prior_evaluation_id': this.priorEvaluationId,
      'prior_basis_fingerprint': priorBasisFingerprint,
      'current_basis_fingerprint': freshFingerprint,
      'prior_evaluation_freshness': 'STALE',
      'change_reasons': ['PLANNING_BASIS_CHANGED'],
    });
    final raw = jsonEncode({
      'transition': transition.toJson(),
      'evaluation': jsonDecode(freshRaw),
    });
    return PlanReevaluateTransportResult(
      transportRequestJson: _transportRequest(currentEvaluationRequestJson),
      transportResponseJson: raw,
      evaluationRequestJson: currentEvaluationRequestJson,
      success: PlanReevaluateSuccessWire.parse(raw),
    );
  }

  String _transportRequest(String currentRequest) => jsonEncode({
        'prior': {
          'evaluation_id': priorEvaluationId,
          'basis_fingerprint': priorBasisFingerprint,
        },
        'current': jsonDecode(currentRequest),
      });

  @override
  void close() {}
}

final class _ControlledPlanApi implements PlanApiClient {
  _ControlledPlanApi({this.delayed = false});

  final bool delayed;
  int evaluateCalls = 0;
  String? lastEvaluationRequest;
  Completer<PlanEvaluateTransportResult>? _pending;

  @override
  Future<PlanEvaluateTransportResult> evaluate({
    required String evaluationRequestJson,
  }) {
    evaluateCalls++;
    lastEvaluationRequest = evaluationRequestJson;
    if (delayed) {
      _pending = Completer<PlanEvaluateTransportResult>();
      return _pending!.future;
    }
    return Future.value(_result(evaluationRequestJson));
  }

  void completeEvaluate() {
    final request = lastEvaluationRequest;
    if (request == null || _pending == null) {
      throw StateError('No pending evaluate request.');
    }
    _pending!.complete(_result(request));
  }

  PlanEvaluateTransportResult _result(String request) {
    final raw = jsonEncode(decisionFixture());
    return PlanEvaluateTransportResult(
      evaluationRequestJson: request,
      evaluationResponseJson: raw,
      response: PlanEvaluateResponseV1.parse(raw),
    );
  }

  @override
  Future<PlanReevaluateTransportResult> reevaluate({
    required String priorEvaluationId,
    required String priorEvaluationResponseJson,
    required String currentEvaluationRequestJson,
  }) {
    throw UnimplementedError();
  }

  @override
  void close() {}
}

final class _RawFailurePlanApi implements PlanApiClient {
  @override
  Future<PlanEvaluateTransportResult> evaluate({
    required String evaluationRequestJson,
  }) {
    throw StateError('simulated unexpected transport/runtime failure');
  }

  @override
  Future<PlanReevaluateTransportResult> reevaluate({
    required String priorEvaluationId,
    required String priorEvaluationResponseJson,
    required String currentEvaluationRequestJson,
  }) {
    throw StateError('simulated unexpected transport/runtime failure');
  }

  @override
  void close() {}
}

final class _FailOncePlanApi implements PlanApiClient {
  _FailOncePlanApi({this.code = 'SOLVER_EXECUTION_FAILED'});
  final String code;
  int evaluateCalls = 0;
  final List<String> requests = [];

  @override
  Future<PlanEvaluateTransportResult> evaluate({
    required String evaluationRequestJson,
  }) async {
    evaluateCalls++;
    requests.add(evaluationRequestJson);
    if (evaluateCalls == 1) {
      throw PlanApiFailure(
        code: code,
        stage: 'planning',
        message: 'simulated transient execution failure',
        statusCode: 500,
      );
    }
    final raw = jsonEncode(decisionFixture());
    return PlanEvaluateTransportResult(
      evaluationRequestJson: evaluationRequestJson,
      evaluationResponseJson: raw,
      response: PlanEvaluateResponseV1.parse(raw),
    );
  }

  @override
  Future<PlanReevaluateTransportResult> reevaluate({
    required String priorEvaluationId,
    required String priorEvaluationResponseJson,
    required String currentEvaluationRequestJson,
  }) {
    throw UnimplementedError();
  }

  @override
  void close() {}
}

final class _FailOnceReevaluationRepository implements EvaluationRepository {
  _FailOnceReevaluationRepository(this.delegate);

  final EvaluationRepository delegate;
  bool failed = false;

  @override
  Future<void> initialize() => delegate.initialize();

  @override
  Future<Evaluation?> evaluationById(String evaluationId) =>
      delegate.evaluationById(evaluationId);

  @override
  Future<Evaluation> persistEvaluation({
    required AnalysisSnapshot analysisSnapshot,
    required String evaluationRequestJson,
    required String evaluationResponseJson,
    required String planningWindowPolicyJson,
  }) =>
      delegate.persistEvaluation(
        analysisSnapshot: analysisSnapshot,
        evaluationRequestJson: evaluationRequestJson,
        evaluationResponseJson: evaluationResponseJson,
        planningWindowPolicyJson: planningWindowPolicyJson,
      );

  @override
  Future<ReevaluationPersistenceResult> persistReevaluation({
    required String priorEvaluationId,
    required ReevaluationTransitionWire transition,
    required String transportRequestJson,
    required String transportResponseJson,
    required String? errorJson,
    AnalysisSnapshot? currentAnalysisSnapshot,
    String? currentEvaluationRequestJson,
    String? currentEvaluationResponseJson,
    String? planningWindowPolicyJson,
  }) {
    if (!failed) {
      failed = true;
      throw StateError('simulated trusted-transition persistence failure');
    }
    return delegate.persistReevaluation(
      priorEvaluationId: priorEvaluationId,
      transition: transition,
      transportRequestJson: transportRequestJson,
      transportResponseJson: transportResponseJson,
      errorJson: errorJson,
      currentAnalysisSnapshot: currentAnalysisSnapshot,
      currentEvaluationRequestJson: currentEvaluationRequestJson,
      currentEvaluationResponseJson: currentEvaluationResponseJson,
      planningWindowPolicyJson: planningWindowPolicyJson,
    );
  }

  @override
  Future<bool> isStale(String evaluationId) => delegate.isStale(evaluationId);

  @override
  Future<void> close() => delegate.close();
}

final class _FailOnceSavedPlanRepository implements SavedPlanRepository {
  _FailOnceSavedPlanRepository(this.delegate, {this.failAccept = true});
  final bool failAccept;
  bool failRefresh = false;
  bool failDetail = false;
  int progressWrites = 0;

  final SavedPlanRepository delegate;
  bool failed = false;

  @override
  Future<void> initialize() => delegate.initialize();

  @override
  Stream<List<SavedPlanSummary>> watchSummaries() => delegate.watchSummaries();

  @override
  Future<List<SavedPlanSummary>> listSummaries() => delegate.listSummaries();

  @override
  Future<SavedPlan?> planForCompetition(String competitionId) =>
      delegate.planForCompetition(competitionId);

  @override
  Future<SavedPlanRevision> acceptEvaluation({
    required String evaluationId,
    required String candidateId,
    required SelectionSource selectionSource,
  }) {
    if (failAccept && !failed) {
      failed = true;
      throw StateError('simulated acceptance transaction failure');
    }
    return delegate.acceptEvaluation(
      evaluationId: evaluationId,
      candidateId: candidateId,
      selectionSource: selectionSource,
    );
  }

  @override
  Future<List<ActiveAcceptedBlock>> activeAcceptedBlocks({
    String? excludingSavedPlanId,
  }) =>
      delegate.activeAcceptedBlocks(
        excludingSavedPlanId: excludingSavedPlanId,
      );

  @override
  Future<SavedPlanDetail?> loadDetail(String savedPlanId) {
    if (failDetail) throw StateError('private sqlite read diagnostic');
    return delegate.loadDetail(savedPlanId);
  }

  @override
  Future<void> updateTaskProgress({
    required String savedPlanTaskId,
    required int progressPercent,
    int? actualMinutes,
    bool clearActualMinutes = false,
  }) {
    progressWrites++;
    return delegate.updateTaskProgress(
        savedPlanTaskId: savedPlanTaskId,
        progressPercent: progressPercent,
        actualMinutes: actualMinutes,
        clearActualMinutes: clearActualMinutes,
      );
  }

  @override
  Future<void> refresh() {
    if (failRefresh) throw StateError('private sqlite refresh diagnostic');
    return delegate.refresh();
  }

  @override
  Future<void> close() => delegate.close();
}

final class _ToggleReadEvaluationRepository
    implements EvaluationRepository {
  _ToggleReadEvaluationRepository(this.delegate);

  final EvaluationRepository delegate;
  bool failReads = false;
  int writes = 0;
  int reevaluationWrites = 0;

  @override
  Future<void> initialize() => delegate.initialize();

  @override
  Future<Evaluation?> evaluationById(String evaluationId) {
    if (failReads) {
      throw StateError('simulated post-commit Evaluation reload failure');
    }
    return delegate.evaluationById(evaluationId);
  }

  @override
  Future<Evaluation> persistEvaluation({
    required AnalysisSnapshot analysisSnapshot,
    required String evaluationRequestJson,
    required String evaluationResponseJson,
    required String planningWindowPolicyJson,
  }) {
    writes++;
    return delegate.persistEvaluation(
        analysisSnapshot: analysisSnapshot,
        evaluationRequestJson: evaluationRequestJson,
        evaluationResponseJson: evaluationResponseJson,
        planningWindowPolicyJson: planningWindowPolicyJson,
      );
  }

  @override
  Future<ReevaluationPersistenceResult> persistReevaluation({
    required String priorEvaluationId,
    required ReevaluationTransitionWire transition,
    required String transportRequestJson,
    required String transportResponseJson,
    required String? errorJson,
    AnalysisSnapshot? currentAnalysisSnapshot,
    String? currentEvaluationRequestJson,
    String? currentEvaluationResponseJson,
    String? planningWindowPolicyJson,
  }) {
    reevaluationWrites++;
    return delegate.persistReevaluation(
        priorEvaluationId: priorEvaluationId,
        transition: transition,
        transportRequestJson: transportRequestJson,
        transportResponseJson: transportResponseJson,
        errorJson: errorJson,
        currentAnalysisSnapshot: currentAnalysisSnapshot,
        currentEvaluationRequestJson: currentEvaluationRequestJson,
        currentEvaluationResponseJson: currentEvaluationResponseJson,
        planningWindowPolicyJson: planningWindowPolicyJson,
      );
  }

  @override
  Future<bool> isStale(String evaluationId) => delegate.isStale(evaluationId);

  @override
  Future<void> close() => delegate.close();
}

final class _FailOnceEvaluationRepository implements EvaluationRepository {
  _FailOnceEvaluationRepository(this.delegate);

  final EvaluationRepository delegate;
  bool failed = false;

  @override
  Future<void> initialize() => delegate.initialize();

  @override
  Future<Evaluation?> evaluationById(String evaluationId) =>
      delegate.evaluationById(evaluationId);

  @override
  Future<Evaluation> persistEvaluation({
    required AnalysisSnapshot analysisSnapshot,
    required String evaluationRequestJson,
    required String evaluationResponseJson,
    required String planningWindowPolicyJson,
  }) {
    if (!failed) {
      failed = true;
      throw StateError('simulated local write failure');
    }
    return delegate.persistEvaluation(
      analysisSnapshot: analysisSnapshot,
      evaluationRequestJson: evaluationRequestJson,
      evaluationResponseJson: evaluationResponseJson,
      planningWindowPolicyJson: planningWindowPolicyJson,
    );
  }

  @override
  Future<ReevaluationPersistenceResult> persistReevaluation({
    required String priorEvaluationId,
    required ReevaluationTransitionWire transition,
    required String transportRequestJson,
    required String transportResponseJson,
    required String? errorJson,
    AnalysisSnapshot? currentAnalysisSnapshot,
    String? currentEvaluationRequestJson,
    String? currentEvaluationResponseJson,
    String? planningWindowPolicyJson,
  }) =>
      delegate.persistReevaluation(
        priorEvaluationId: priorEvaluationId,
        transition: transition,
        transportRequestJson: transportRequestJson,
        transportResponseJson: transportResponseJson,
        errorJson: errorJson,
        currentAnalysisSnapshot: currentAnalysisSnapshot,
        currentEvaluationRequestJson: currentEvaluationRequestJson,
        currentEvaluationResponseJson: currentEvaluationResponseJson,
        planningWindowPolicyJson: planningWindowPolicyJson,
      );

  @override
  Future<bool> isStale(String evaluationId) => delegate.isStale(evaluationId);

  @override
  Future<void> close() => delegate.close();
}

Future<Evaluation> _persistAndAcceptPrior(
  DriftEvaluationRepository evaluations,
  DriftSavedPlanRepository savedPlans,
  AnalysisSnapshot snapshot,
) async {
  final prior = await evaluations.persistEvaluation(
    analysisSnapshot: snapshot,
    evaluationRequestJson: _priorRequest(),
    evaluationResponseJson: jsonEncode(decisionFixture()),
    planningWindowPolicyJson: jsonEncode({
      'policy_version': 'planning-window-policy-v1',
      'timezone': 'Asia/Jakarta',
      'start_local': '09:00',
      'end_local': '20:00',
    }),
  );
  await savedPlans.acceptEvaluation(
    evaluationId: prior.id,
    candidateId: primaryId,
    selectionSource: SelectionSource.primary,
  );
  return prior;
}

String _decisionResponse({
  required String evaluationIdValue,
  required String basisFingerprint,
}) {
  final raw = jsonEncode(decisionFixture())
      .replaceAll(evaluationId, evaluationIdValue)
      .replaceAll(List.filled(64, 'b').join(), basisFingerprint);
  return raw;
}

Future<void> _pumpUi(
  WidgetTester tester, {
  int frames = 20,
}) async {
  for (var index = 0; index < frames; index++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<void> _waitFor(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition was not reached.');
}

PlanningTaskDraft _task() => PlanningTaskDraft(
      taskId: 'task-draft',
      name: 'Build prototype',
      mandatory: true,
      dependencies: const [],
      effortMinMinutes: 30,
      effortLikelyMinutes: 30,
      effortMaxMinutes: 30,
      assumptions: const ['Confirmed effort.'],
    );

AnalysisSnapshot _snapshot() => _snapshotFor(
      id: 'snapshot-2',
      competitionId: 'competition-1',
    );

AnalysisSnapshot _snapshotFor({
  required String id,
  required String competitionId,
}) {
  final hash = List.filled(64, 'a').join();
  return AnalysisSnapshot(
    id: id,
    competitionId: competitionId,
    reportVersion: 2,
    assemblyMaterialFingerprint: hash,
    sourceSetFingerprint: null,
    wireFingerprint: List.filled(64, 'f').join(),
    reportChanged: true,
    responseJson: jsonEncode({
      'report_bundle': {
        'report': {
          'competition_id': competitionId,
          'report_version': 2,
          'canonical_fields': {
            'submission_deadline': {
              'state': 'VERIFIED',
              'value': '2026-10-10T16:00:00Z',
              'normalized_value': '2026-10-10T16:00:00Z',
            },
          },
        },
        'ref': {
          'assembly_material_fingerprint': hash,
        },
      },
    }),
    cachedAtEpochMs: 1,
  );
}

Future<void> _seedSnapshot(
  AppDatabase db,
  AnalysisSnapshot snapshot,
) async {
  await db.customStatement(
    '''
INSERT INTO competitions (
  id, created_at_epoch_ms, updated_at_epoch_ms
) VALUES (?, ?, ?)
''',
    [snapshot.competitionId, 1, 1],
  );
  await db.customStatement(
    '''
INSERT INTO analysis_snapshots (
  id, competition_id, report_version, assembly_material_fingerprint,
  source_set_fingerprint, wire_fingerprint, report_changed,
  response_json, cached_at_epoch_ms
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
    [
      snapshot.id,
      snapshot.competitionId,
      snapshot.reportVersion,
      snapshot.assemblyMaterialFingerprint,
      null,
      snapshot.wireFingerprint,
      1,
      snapshot.responseJson,
      snapshot.cachedAtEpochMs,
    ],
  );
}

String _priorRequest() => jsonEncode({
      'report_bundle': {
        'report': {
          'competition_id': 'competition-1',
          'report_version': 2,
          'canonical_fields': {
            'competition_name': {
              'state': 'VERIFIED',
              'value': 'Demo Hackathon',
              'normalized_value': 'Demo Hackathon',
            },
            'submission_deadline': {
              'state': 'VERIFIED',
              'value': '2026-10-10T16:00:00Z',
              'normalized_value': '2026-10-10T16:00:00Z',
            },
          },
        },
        'ref': {
          'assembly_material_fingerprint': List.filled(64, 'a').join(),
        },
      },
      'readiness_context': {
        'user': {
          'age': 21,
          'student_status': true,
          'country': 'ID',
        },
        'selected_scope': 'student',
        'require_technology_information': false,
      },
      'planning': {
        'workload': {
          'tasks': [_task().toWire()],
          'assumptions': <Object?>[],
        },
        'availability': {
          'preferences': {
            'timezone': 'Asia/Jakarta',
            'max_project_minutes_per_day': 300,
            'preferred_focus_minutes': 100,
            'buffer_target_minutes': 45,
          },
        },
      },
    });


void _compactViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 720);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

final class _FailingScheduleReads implements ScheduleRepository {
  _FailingScheduleReads(this.delegate);
  final ScheduleRepository delegate;
  bool failReads = false;
  @override
  Future<void> initialize() => delegate.initialize();
  @override
  Future<ScheduleState> loadState() {
    if (failReads) throw StateError('private sqlite context diagnostic');
    return delegate.loadState();
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ThrowingAnalysisRead implements AnalysisRepository {
  int reads = 0;
  @override
  Future<AnalysisSnapshot?> latestSnapshot(String competitionId) async {
    reads++;
    throw StateError('private sqlite context diagnostic');
  }
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}


Future<void> _showRecoveryControl(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 220,
      scrollable: find.byType(Scrollable).first);
  await tester.pump();
}
