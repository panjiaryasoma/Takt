import 'package:flutter/foundation.dart';

import '../models/decision_intent.dart';
import '../models/enums.dart';
import '../models/evaluation_session.dart';
import '../models/plan_evaluation_wire.dart';

/// Identity token for one confirmation, holding the exact immutable snapshot
/// displayed to the user. Only this ViewModel can construct a valid token.
final class AcceptConfirmation {
  const AcceptConfirmation._(this.session, this.candidateId, this.selectionSource);
  final EvaluationSession session;
  final String candidateId;
  final SelectionSource selectionSource;
  String get sessionId => session.sessionId;
  int get generation => session.generation;
  String get evaluationId => session.parsedResponse.evaluationId;
}

/// Ephemeral component state. No repositories, request counters or HTTP client.
class DecisionReportViewModel extends ChangeNotifier {
  DecisionReportViewModel({
    required EvaluationSession? session,
    required int currentInputRevision,
  }) {
    updateHost(session: session, currentInputRevision: currentInputRevision);
  }

  EvaluationSession? _session;
  int _currentInputRevision = 0;
  bool _invalidated = false;
  bool _dismissed = false;
  String? _selectedCandidateId;
  AcceptConfirmation? _confirmation;
  AcceptConfirmation? _handoff;
  bool _handoffComplete = false;
  bool _handoffFailed = false;

  EvaluationSession? get session => _session;
  int get currentInputRevision => _currentInputRevision;
  /// Presentation-only invalidation: the displayed session no longer matches
  /// the host's current input revision. This is not persisted SUPERSEDED state.
  bool get isSessionOutdated => _session != null && _invalidated;
  bool get isDismissed => _dismissed;
  bool get isActive => _session != null && !_invalidated && !_dismissed;
  bool get handoffPending => _handoff != null;
  bool get handoffComplete => _handoffComplete;
  bool get handoffFailed => _handoffFailed;
  AcceptConfirmation? get pendingConfirmation => _confirmation;
  PlanningDecisionV1? get planning => _session?.parsedResponse.planning;
  String? get systemPrimaryCandidateId => planning?.recommendation?.primaryCandidate.candidateId;
  String? get selectedCandidateId => _selectedCandidateId;
  PublicCandidateV1? get selectedCandidate => planning?.candidate(_selectedCandidateId);

  /// The host supplies its current snapshot/revision. A replacement resets UI
  /// state even when inputRevision did not change (e.g. fresh server-time run).
  void updateHost({required EvaluationSession? session, required int currentInputRevision}) {
    if (currentInputRevision < 0) throw ArgumentError.value(currentInputRevision);
    final replaced = !identical(_session, session);
    final changed = replaced || _currentInputRevision != currentInputRevision;
    if (!changed) return;
    _session = session;
    _currentInputRevision = currentInputRevision;
    if (replaced) {
      _invalidated = false;
      _dismissed = false;
      _confirmation = null;
      _handoff = null;
      _handoffComplete = false;
      _handoffFailed = false;
      _selectedCandidateId = systemPrimaryCandidateId;
    }
    if (session != null && session.inputRevision != currentInputRevision) {
      _invalidated = true;
      _selectedCandidateId = null;
      _confirmation = null;
      _handoff = null;
      _handoffComplete = false;
      _handoffFailed = false;
    }
    notifyListeners();
  }

  /// Backend [allowedActions] remains the only domain action authority.
  /// Mobile may only further disable an existing action for local session/
  /// handoff safety. It must never reconstruct policy from feasibility/readiness.
  bool can(RecommendationAction action) => isActive &&
      !handoffPending &&
      !_handoffComplete &&
      (planning?.allowedActions.contains(action) ?? false);

  bool chooseCandidate(String candidateId) {
    if (!can(RecommendationAction.chooseAlternative) ||
        planning?.candidate(candidateId) == null) {
      return false;
    }
    _confirmation = null;
    _selectedCandidateId = candidateId;
    _handoffFailed = false;
    notifyListeners();
    return true;
  }

  AcceptConfirmation? beginAccept() {
    if (!can(RecommendationAction.accept) || selectedCandidate == null) return null;
    // Repeated taps cannot create a second confirmation for the same UI state.
    if (_confirmation != null) return _confirmation;
    _confirmation = AcceptConfirmation._(_session!, _selectedCandidateId!,
        _selectedCandidateId == systemPrimaryCandidateId ? SelectionSource.primary : SelectionSource.alternative);
    _handoffFailed = false;
    notifyListeners();
    return _confirmation;
  }

  void cancelConfirmation(AcceptConfirmation token) {
    if (!identical(_confirmation, token)) return;
    _confirmation = null;
    notifyListeners();
  }

  AcceptCandidateIntent? confirmAccept(AcceptConfirmation token) {
    final valid = identical(_confirmation, token) && identical(_session, token.session) &&
        token.generation == _session?.generation && token.sessionId == _session?.sessionId &&
        token.session.inputRevision == _currentInputRevision &&
        token.evaluationId == _session?.parsedResponse.evaluationId &&
        token.candidateId == _selectedCandidateId &&
        planning?.candidate(token.candidateId) != null && can(RecommendationAction.accept);
    if (!valid) {
      cancelConfirmation(token);
      return null;
    }
    _confirmation = null;
    _handoff = token;
    notifyListeners();
    return AcceptCandidateIntent(
      sessionId: token.sessionId,
      evaluationId: token.evaluationId,
      candidateId: token.candidateId,
      selectionSource: token.selectionSource,
    );
  }

  void resetFailedHandoff() {
    if (!_handoffFailed || _handoff != null) return;
    _handoffFailed = false;
    _handoffComplete = false;
    notifyListeners();
  }

  /// Ignore completions from a replaced/invalidated session. A failed handoff
  /// permits a new explicit confirmation; it is never retried automatically.
  void finishHandoff(AcceptConfirmation token, {bool failed = false}) {
    if (!identical(_handoff, token) || !identical(_session, token.session)) return;
    _handoff = null;
    _handoffComplete = !failed;
    _handoffFailed = failed;
    notifyListeners();
  }

  EditConstraintsIntent? editConstraints() {
    if (!can(RecommendationAction.editConstraints)) return null;
    _confirmation = null;
    final intent = EditConstraintsIntent(sessionId: _session!.sessionId,
        evaluationId: _session!.parsedResponse.evaluationId, inputRevision: _session!.inputRevision);
    notifyListeners();
    return intent;
  }

  IgnoreRecommendationIntent? ignore() {
    if (!can(RecommendationAction.ignore)) return null;
    final intent = IgnoreRecommendationIntent(sessionId: _session!.sessionId,
        evaluationId: _session!.parsedResponse.evaluationId, inputRevision: _session!.inputRevision);
    _confirmation = null;
    _selectedCandidateId = null;
    _dismissed = true;
    notifyListeners();
    return intent;
  }
}
