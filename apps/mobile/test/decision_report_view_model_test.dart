import 'package:flutter_test/flutter_test.dart';
import 'package:takt_mobile/models/enums.dart';
import 'package:takt_mobile/models/evaluation_session.dart';
import 'package:takt_mobile/viewmodels/decision_report_view_model.dart';

import 'support/decision_fixture.dart';

void main() {
  DecisionReportViewModel model([EvaluationSession? session]) =>
      DecisionReportViewModel(session: session ?? testSession(), currentInputRevision: 3);

  test('alternative changes selection without changing primary or accepting', () {
    final vm = model();
    addTearDown(vm.dispose);
    expect(vm.selectedCandidateId, primaryId);
    expect(vm.chooseCandidate(alternativeId), isTrue);
    expect(vm.systemPrimaryCandidateId, primaryId);
    expect(vm.selectedCandidateId, alternativeId);
    expect(vm.handoffComplete, isFalse);
    final token = vm.beginAccept()!;
    expect(vm.beginAccept(), same(token));
    final intent = vm.confirmAccept(token)!;
    expect(intent.candidateId, alternativeId);
    expect(intent.selectionSource, SelectionSource.alternative);
    expect(intent.sessionId, token.sessionId);
    expect(intent.evaluationId, token.evaluationId);
    expect(vm.handoffPending, isTrue);
    expect(vm.confirmAccept(token), isNull);
    expect(vm.beginAccept(), isNull);
    expect(vm.chooseCandidate(primaryId), isFalse);
    vm.finishHandoff(token);
    expect(vm.handoffComplete, isTrue);
    expect(vm.beginAccept(), isNull);
  });

  test('session replacement at same revision cancels old confirmation', () {
    final vm = model();
    addTearDown(vm.dispose);
    vm.chooseCandidate(alternativeId);
    final old = vm.beginAccept()!;
    vm.updateHost(session: testSession(generation: 13), currentInputRevision: 3);
    expect(vm.pendingConfirmation, isNull);
    expect(vm.selectedCandidateId, primaryId);
    final current = vm.beginAccept()!;
    expect(vm.confirmAccept(old), isNull);
    expect(vm.pendingConfirmation, same(current));
    expect(vm.confirmAccept(current)!.sessionId, 'session-13');
  });

  test('revision invalidation clears selection and requires a fresh session', () {
    final session = testSession();
    final vm = model(session);
    addTearDown(vm.dispose);
    final old = vm.beginAccept()!;
    vm.updateHost(session: session, currentInputRevision: 4);
    expect(vm.isSessionOutdated, isTrue);
    expect(vm.selectedCandidateId, isNull);
    expect(vm.pendingConfirmation, isNull);
    expect(vm.confirmAccept(old), isNull);
    expect(vm.can(RecommendationAction.accept), isFalse);
    vm.updateHost(session: session, currentInputRevision: 3);
    expect(vm.isSessionOutdated, isTrue);
    vm.updateHost(session: testSession(generation: 13, revision: 4), currentInputRevision: 4);
    expect(vm.isSessionOutdated, isFalse);
    expect(vm.selectedCandidateId, primaryId);
  });

  test('selection change cancels confirmation and binds the new candidate', () {
    final vm = model();
    addTearDown(vm.dispose);
    final old = vm.beginAccept()!;
    vm.chooseCandidate(alternativeId);
    expect(vm.confirmAccept(old), isNull);
    expect(vm.confirmAccept(vm.beginAccept()!)!.candidateId, alternativeId);
  });

  test('failed handoff requires new consent; late completion cannot affect new session', () {
    final vm = model();
    addTearDown(vm.dispose);
    final old = vm.beginAccept()!;
    vm.confirmAccept(old);
    vm.finishHandoff(old, failed: true);
    expect(vm.handoffFailed, isTrue);
    expect(vm.confirmAccept(old), isNull);
    final retry = vm.beginAccept()!;
    expect(retry, isNot(same(old)));
    vm.confirmAccept(retry);
    vm.updateHost(session: testSession(generation: 13), currentInputRevision: 3);
    vm.finishHandoff(retry);
    expect(vm.handoffComplete, isFalse);
    expect(vm.can(RecommendationAction.accept), isTrue);
  });

  test('edit emits identity only; ignore dismisses without changing response', () {
    final vm = model();
    addTearDown(vm.dispose);
    final response = vm.session!.evaluationResponseJson;
    vm.beginAccept();
    final edit = vm.editConstraints()!;
    expect(edit.inputRevision, 3);
    expect(edit.evaluationId, evaluationId);
    expect(vm.pendingConfirmation, isNull);
    final ignore = vm.ignore()!;
    expect(ignore.sessionId, vm.session!.sessionId);
    expect(vm.selectedCandidateId, isNull);
    expect(vm.isDismissed, isTrue);
    expect(vm.session!.evaluationResponseJson, response);
    expect(vm.beginAccept(), isNull);
    expect(vm.ignore(), isNull);
  });

  test('blocked, infeasible, absent and single-candidate sessions gate actions', () {
    final blocked = model(testSession(readiness: 'NEEDS_REVIEW'));
    final infeasible = model(testSession(feasibility: 'NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS'));
    final single = model(testSession(alternatives: false));
    final absent = DecisionReportViewModel(session: null, currentInputRevision: 3);
    for (final vm in [blocked, infeasible, single, absent]) { addTearDown(vm.dispose); }
    expect(blocked.planning, isNull);
    expect(blocked.beginAccept(), isNull);
    expect(infeasible.beginAccept(), isNull);
    expect(infeasible.editConstraints(), isNotNull);
    expect(infeasible.ignore(), isNotNull);
    expect(single.chooseCandidate(primaryId), isFalse);
    expect(single.chooseCandidate('absent'), isFalse);
    expect(single.beginAccept(), isNotNull);
    expect(absent.isActive, isFalse);
    expect(absent.beginAccept(), isNull);
  });
}
