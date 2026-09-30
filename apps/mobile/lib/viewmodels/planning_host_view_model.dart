import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/remote/plan_api_client.dart';
import '../data/repositories/evaluation_repository.dart';
import '../data/repositories/saved_plan_repository.dart';
import '../data/repositories/schedule_repository.dart';
import '../models/analysis_snapshot.dart';
import '../models/decision_intent.dart';
import '../models/evaluation.dart';
import '../models/evaluation_session.dart';
import '../models/planning_input_draft.dart';
import '../models/planning_preferences.dart';
import '../models/recovery_policy.dart';
import '../models/saved_plan.dart';
import '../services/planning_request_assembler.dart';

enum PlanningHostPhase {
  idle,
  loading,
  setup,
  requesting,
  persisting,
  persistenceError,
  decision,
  unchanged,
  accepted,
  error,
}

final class PlanningHostFailure {
  const PlanningHostFailure({
    required this.code,
    required this.message,
    required this.recoveryClass,
    this.stage = 'local',
    this.statusCode,
  });

  final String code;
  final String message;
  final RecoveryClass recoveryClass;
  final String stage;
  final int? statusCode;

  bool get retryable => recoveryClass == RecoveryClass.retrySameInput;
}

final class PlanningHostViewModel extends ChangeNotifier {
  PlanningHostViewModel({
    required PlanApiClient apiClient,
    required ScheduleRepository scheduleRepository,
    required EvaluationRepository evaluationRepository,
    required SavedPlanRepository savedPlanRepository,
    PlanningRequestAssembler? assembler,
    this.closeScheduleRepositoryOnDispose = false,
    this.closeEvaluationRepositoryOnDispose = false,
    this.closeSavedPlanRepositoryOnDispose = false,
  })  : _apiClient = apiClient,
        _scheduleRepository = scheduleRepository,
        _evaluationRepository = evaluationRepository,
        _savedPlanRepository = savedPlanRepository,
        _assembler = assembler ?? PlanningRequestAssembler();

  final PlanApiClient _apiClient;
  final ScheduleRepository _scheduleRepository;
  final EvaluationRepository _evaluationRepository;
  final SavedPlanRepository _savedPlanRepository;
  final PlanningRequestAssembler _assembler;
  final bool closeScheduleRepositoryOnDispose;
  final bool closeEvaluationRepositoryOnDispose;
  final bool closeSavedPlanRepositoryOnDispose;

  PlanningHostPhase _phase = PlanningHostPhase.idle;
  AnalysisSnapshot? _analysisSnapshot;
  PlanningDraft? _draft;
  SavedPlan? _savedPlan;
  Evaluation? _priorEvaluation;
  EvaluationSession? _activeSession;
  PlanningHostFailure? _failure;
  _PendingPersistence? _pendingPersistence;
  _PlanRequestContext? _lastRequest;
  _PendingAcceptance? _pendingAcceptance;
  bool _acceptanceSaving = false;
  String? _message;
  int _inputRevision = 0;
  int _generation = 0;
  bool _forceFreshBaseline = false;

  PlanningHostPhase get phase => _phase;
  AnalysisSnapshot? get analysisSnapshot => _analysisSnapshot;
  PlanningDraft? get draft => _draft;
  SavedPlan? get savedPlan => _savedPlan;
  EvaluationSession? get activeSession => _activeSession;
  PlanningHostFailure? get failure => _failure;
  String? get message => _message;
  int get inputRevision => _inputRevision;
  int get generation => _generation;
  bool get hasAcceptedPlan => _savedPlan != null;
  bool get busy => _phase == PlanningHostPhase.loading ||
      _phase == PlanningHostPhase.requesting ||
      _phase == PlanningHostPhase.persisting ||
      _acceptanceSaving;
  bool get canRetryPersistence =>
      _phase == PlanningHostPhase.persistenceError &&
      _pendingPersistence != null;
  PersistenceExitKind? get persistenceExitKind => switch (_pendingPersistence) {
        _PendingInitial() || _PendingReevaluationSuccess() =>
          PersistenceExitKind.discardableResult,
        _PendingReevaluationFailure() =>
          PersistenceExitKind.correctnessBearing,
        null => null,
      };
  bool get canDiscardPendingResult =>
      persistenceExitKind == PersistenceExitKind.discardableResult;
  bool get hasKnownUnpersistedStaleWitness {
    final pending = _pendingPersistence;
    return pending is _PendingReevaluationFailure &&
        pending.failure.transition?.priorEvaluationFreshness == 'STALE';
  }
  bool get acceptanceSaving => _acceptanceSaving;
  bool get canRetryAcceptancePersistence =>
      _pendingAcceptance != null && !_acceptanceSaving;
  bool get canCancelPendingAcceptance =>
      _pendingAcceptance != null && !_acceptanceSaving;
  bool get hasPendingAcceptance => _pendingAcceptance != null;
  bool get inputsLocked => busy || canRetryPersistence || hasPendingAcceptance;
  bool get canRetryRequest =>
      _phase == PlanningHostPhase.error &&
      _failure?.recoveryClass == RecoveryClass.retrySameInput &&
      _lastRequest != null;
  bool get canCreateFreshBaseline =>
      _phase == PlanningHostPhase.error &&
      _failure?.code == 'UNSUPPORTED_REEVALUATION_CONTRACT' &&
      _savedPlan != null;

  Future<void> startPlanning(AnalysisSnapshot snapshot) async {
    if (persistenceExitKind == PersistenceExitKind.correctnessBearing) {
      _setPersistenceFailure(
        StateError(
          'A trusted re-evaluation transition still requires local persistence.',
        ),
      );
      return;
    }
    if (_pendingAcceptance != null) {
      _failure = const PlanningHostFailure(
        code: 'LOCAL_ACCEPT_PERSISTENCE_FAILED',
        message:
            'Resolve or cancel the pending acceptance save before opening another planning context.',
        recoveryClass: RecoveryClass.noAutomaticRecovery,
      );
      notifyListeners();
      return;
    }

    final contextGeneration = ++_generation;
    _phase = PlanningHostPhase.loading;
    _analysisSnapshot = null;
    _draft = null;
    _savedPlan = null;
    _priorEvaluation = null;
    _activeSession = null;
    _pendingPersistence = null;
    _lastRequest = null;
    _pendingAcceptance = null;
    _acceptanceSaving = false;
    _failure = null;
    _message = null;
    _inputRevision = 0;
    _forceFreshBaseline = false;
    notifyListeners();

    try {
      await _scheduleRepository.initialize();
      await _evaluationRepository.initialize();
      await _savedPlanRepository.initialize();

      final schedule = await _scheduleRepository.loadState();
      final plan =
          await _savedPlanRepository.planForCompetition(snapshot.competitionId);

      PlanningDraft nextDraft;
      Evaluation? prior;
      if (plan == null) {
        nextDraft = PlanningDraft(
          readinessContext: const ReadinessContextDraft(),
          tasks: const [],
          preferences: schedule.preferences,
          windowPolicy: PlanningWindowPolicyV1.defaults(
            schedule.preferences.timezone,
          ),
        );
      } else {
        final detail = await _savedPlanRepository.loadDetail(plan.id);
        if (detail == null) {
          throw const FormatException(
            'Accepted plan could not be reloaded from persistence.',
          );
        }
        prior = await _evaluationRepository.evaluationById(
          detail.summary.currentRevision.evaluationId,
        );
        if (prior == null) {
          throw const FormatException(
            'Accepted plan references a missing evaluation.',
          );
        }
        nextDraft = _draftFromEvaluation(prior);
      }

      if (contextGeneration != _generation) return;

      _analysisSnapshot = snapshot;
      _savedPlan = plan;
      _priorEvaluation = prior;
      _draft = nextDraft;
      _inputRevision = 0;
      _forceFreshBaseline = false;
      _phase = PlanningHostPhase.setup;
      notifyListeners();
    } on Object catch (error) {
      if (contextGeneration != _generation) return;
      _phase = PlanningHostPhase.error;
      _failure = PlanningHostFailure(
        code: 'LOCAL_CONTEXT_INVALID',
        message: 'Planning context could not be prepared: $error',
        recoveryClass: RecoveryClass.reloadContext,
      );
      notifyListeners();
    }
  }

  void commitDraft(PlanningDraft next) {
    _mutateDraft(next);
  }

  void replaceReadiness(ReadinessContextDraft readiness) {
    _mutateDraft(_requireDraft().copyWith(readinessContext: readiness));
  }

  void addTask(PlanningTaskDraft task) {
    final current = _requireDraft();
    _mutateDraft(current.copyWith(tasks: [...current.tasks, task]));
  }

  void updateTask(PlanningTaskDraft task) {
    final current = _requireDraft();
    final index =
        current.tasks.indexWhere((item) => item.taskId == task.taskId);
    if (index < 0) {
      throw ArgumentError.value(task.taskId, 'task.taskId');
    }
    final next = [...current.tasks];
    next[index] = task;
    _mutateDraft(current.copyWith(tasks: next));
  }

  void removeTask(String taskId) {
    final current = _requireDraft();
    if (current.tasks.any((task) => task.dependencies.contains(taskId))) {
      throw const FormatException(
        'Remove dependent task links before deleting this task.',
      );
    }
    _mutateDraft(
      current.copyWith(
        tasks: current.tasks
            .where((task) => task.taskId != taskId)
            .toList(growable: false),
      ),
    );
  }

  void replacePreferences(PlanningPreferences preferences) {
    _mutateDraft(_requireDraft().copyWith(preferences: preferences));
  }

  void replaceWindowPolicy(PlanningWindowPolicyV1 policy) {
    final current = _requireDraft();
    final preferences = current.preferences.timezone == policy.timezone
        ? current.preferences
        : current.preferences.copyWith(
            timezone: policy.timezone,
            updatedAtEpochMs: current.preferences.updatedAtEpochMs,
          );
    _mutateDraft(
      current.copyWith(
        preferences: preferences,
        windowPolicy: policy,
      ),
    );
  }

  Future<void> useCurrentDefaults() async {
    final state = await _scheduleRepository.loadState();
    final current = _requireDraft();
    _mutateDraft(
      current.copyWith(
        preferences: state.preferences,
        windowPolicy: current.windowPolicy.copyWith(
          timezone: state.preferences.timezone,
        ),
      ),
    );
  }

  Future<void> evaluate() async {
    if (busy) return;
    final snapshot = _analysisSnapshot;
    final draft = _draft;
    if (snapshot == null || draft == null) {
      _setLocalFailure(
        'PLANNING_INPUT_UNAVAILABLE',
        'No persisted analysis is selected for planning.',
      );
      return;
    }

    final capturedGeneration = ++_generation;
    final capturedRevision = _inputRevision;
    _phase = PlanningHostPhase.requesting;
    _failure = null;
    _message = null;
    _pendingPersistence = null;
    notifyListeners();

    late final PlanningAssembly assembly;
    try {
      final schedule = await _scheduleRepository.loadState();
      final accepted = await _savedPlanRepository.activeAcceptedBlocks(
        excludingSavedPlanId: _savedPlan?.id,
      );
      assembly = _assembler.assemble(
        analysisSnapshot: snapshot,
        draft: draft,
        schedule: schedule,
        acceptedBlocks: accepted,
      );
    } on PlanningInputException catch (error) {
      if (_isCurrent(capturedGeneration, capturedRevision)) {
        _phase = PlanningHostPhase.setup;
        _failure = PlanningHostFailure(
          code: error.code,
          message: error.message,
          recoveryClass: RecoveryClass.editConstraints,
        );
        notifyListeners();
      }
      return;
    } on Object catch (error) {
      if (_isCurrent(capturedGeneration, capturedRevision)) {
        _setLocalFailure(
          'PLANNING_INPUT_UNAVAILABLE',
          'Planning input could not be assembled: $error',
        );
      }
      return;
    }

    if (!_isCurrent(capturedGeneration, capturedRevision)) return;

    if (_savedPlan == null || _forceFreshBaseline) {
      _lastRequest = _FreshPlanRequest(
        generation: capturedGeneration,
        revision: capturedRevision,
        snapshot: snapshot,
        assembly: assembly,
      );
      await _evaluateFresh(
        snapshot: snapshot,
        assembly: assembly,
        generation: capturedGeneration,
        revision: capturedRevision,
      );
      return;
    }

    final prior = _priorEvaluation;
    if (prior == null) {
      _setLocalFailure(
        'LOCAL_CONTEXT_INVALID',
        'The accepted plan has no persisted prior evaluation.',
      );
      return;
    }
    _lastRequest = _ReevaluationPlanRequest(
      generation: capturedGeneration,
      revision: capturedRevision,
      snapshot: snapshot,
      prior: prior,
      assembly: assembly,
    );
    await _reevaluate(
      snapshot: snapshot,
      prior: prior,
      assembly: assembly,
      generation: capturedGeneration,
      revision: capturedRevision,
    );
  }

  Future<void> retryRequest() async {
    final request = _lastRequest;
    if (!canRetryRequest || request == null ||
        !_isCurrent(request.generation, request.revision)) {
      return;
    }
    _phase = PlanningHostPhase.requesting;
    _failure = null;
    _message = null;
    notifyListeners();

    switch (request) {
      case _FreshPlanRequest():
        await _evaluateFresh(
          snapshot: request.snapshot,
          assembly: request.assembly,
          generation: request.generation,
          revision: request.revision,
        );
      case _ReevaluationPlanRequest():
        await _reevaluate(
          snapshot: request.snapshot,
          prior: request.prior,
          assembly: request.assembly,
          generation: request.generation,
          revision: request.revision,
        );
    }
  }

  Future<void> _evaluateFresh({
    required AnalysisSnapshot snapshot,
    required PlanningAssembly assembly,
    required int generation,
    required int revision,
  }) async {
    try {
      final transport = await _apiClient.evaluate(
        evaluationRequestJson: assembly.requestJson,
      );
      if (!_isCurrent(generation, revision)) return;

      _lastRequest = null;
      _phase = PlanningHostPhase.persisting;
      notifyListeners();
      try {
        final persisted = await _evaluationRepository.persistEvaluation(
          analysisSnapshot: snapshot,
          evaluationRequestJson: transport.evaluationRequestJson,
          evaluationResponseJson: transport.evaluationResponseJson,
          planningWindowPolicyJson: assembly.windowPolicyJson,
        );
        if (!_isCurrent(generation, revision)) return;
        await _publishPersisted(persisted, generation, revision);
      } on Object catch (error) {
        if (!_isCurrent(generation, revision)) return;
        _pendingPersistence = _PendingInitial(
          generation: generation,
          revision: revision,
          snapshot: snapshot,
          assembly: assembly,
          transport: transport,
        );
        _setPersistenceFailure(error);
      }
    } on PlanApiFailure catch (error) {
      if (!_isCurrent(generation, revision)) return;
      _setApiFailure(error);
    }
  }

  Future<void> _reevaluate({
    required AnalysisSnapshot snapshot,
    required Evaluation prior,
    required PlanningAssembly assembly,
    required int generation,
    required int revision,
  }) async {
    try {
      final transport = await _apiClient.reevaluate(
        priorEvaluationId: prior.id,
        priorEvaluationResponseJson: prior.responseJson,
        currentEvaluationRequestJson: assembly.requestJson,
      );
      if (!_isCurrent(generation, revision)) return;

      _lastRequest = null;
      _phase = PlanningHostPhase.persisting;
      notifyListeners();
      try {
        final persisted = await _persistReevaluationSuccess(
          snapshot: snapshot,
          prior: prior,
          assembly: assembly,
          transport: transport,
        );
        if (!_isCurrent(generation, revision)) return;
        if (persisted.evaluation == null) {
          _activeSession = null;
          _phase = PlanningHostPhase.unchanged;
          _message = 'No material planning changes were found.';
          _failure = null;
          notifyListeners();
          return;
        }
        await _publishPersisted(
          persisted.evaluation!,
          generation,
          revision,
        );
      } on Object catch (error) {
        if (!_isCurrent(generation, revision)) return;
        _pendingPersistence = _PendingReevaluationSuccess(
          generation: generation,
          revision: revision,
          snapshot: snapshot,
          prior: prior,
          assembly: assembly,
          transport: transport,
        );
        _setPersistenceFailure(error);
      }
    } on PlanApiFailure catch (error) {
      if (!_isCurrent(generation, revision)) return;
      final transition = error.transition;
      final request = error.transportRequestJson;
      final response = error.transportResponseJson;
      final errorJson = error.errorJson;
      if (transition != null &&
          request != null &&
          response != null &&
          errorJson != null) {
        _lastRequest = null;
        try {
          await _evaluationRepository.persistReevaluation(
            priorEvaluationId: prior.id,
            transition: transition,
            transportRequestJson: request,
            transportResponseJson: response,
            errorJson: errorJson,
          );
          await _savedPlanRepository.refresh();
        } on Object catch (persistenceError) {
          _pendingPersistence = _PendingReevaluationFailure(
            generation: generation,
            revision: revision,
            prior: prior,
            failure: error,
          );
          _setPersistenceFailure(persistenceError);
          return;
        }
      }
      _setApiFailure(error);
    }
  }

  Future<ReevaluationPersistenceResult> _persistReevaluationSuccess({
    required AnalysisSnapshot snapshot,
    required Evaluation prior,
    required PlanningAssembly assembly,
    required PlanReevaluateTransportResult transport,
  }) {
    final success = transport.success;
    final responseJson = success.evaluationResponseJson;
    return _evaluationRepository.persistReevaluation(
      priorEvaluationId: prior.id,
      transition: success.transition,
      transportRequestJson: transport.transportRequestJson,
      transportResponseJson: transport.transportResponseJson,
      errorJson: null,
      currentAnalysisSnapshot:
          responseJson == null ? null : snapshot,
      currentEvaluationRequestJson:
          responseJson == null ? null : transport.evaluationRequestJson,
      currentEvaluationResponseJson: responseJson,
      planningWindowPolicyJson:
          responseJson == null ? null : assembly.windowPolicyJson,
    );
  }

  Future<void> retryPersistence() async {
    final pending = _pendingPersistence;
    if (pending == null ||
        !_isCurrent(pending.generation, pending.revision)) {
      return;
    }
    _phase = PlanningHostPhase.persisting;
    _failure = null;
    notifyListeners();

    try {
      switch (pending) {
        case _PendingInitial():
          final persisted = await _evaluationRepository.persistEvaluation(
            analysisSnapshot: pending.snapshot,
            evaluationRequestJson: pending.transport.evaluationRequestJson,
            evaluationResponseJson: pending.transport.evaluationResponseJson,
            planningWindowPolicyJson: pending.assembly.windowPolicyJson,
          );
          _pendingPersistence = null;
          await _publishPersisted(
            persisted,
            pending.generation,
            pending.revision,
          );
          return;
        case _PendingReevaluationSuccess():
          final persisted = await _persistReevaluationSuccess(
            snapshot: pending.snapshot,
            prior: pending.prior,
            assembly: pending.assembly,
            transport: pending.transport,
          );
          _pendingPersistence = null;
          if (persisted.evaluation == null) {
            _phase = PlanningHostPhase.unchanged;
            _message = 'No material planning changes were found.';
            notifyListeners();
          } else {
            await _publishPersisted(
              persisted.evaluation!,
              pending.generation,
              pending.revision,
            );
          }
          return;
        case _PendingReevaluationFailure():
          final error = pending.failure;
          await _evaluationRepository.persistReevaluation(
            priorEvaluationId: pending.prior.id,
            transition: error.transition!,
            transportRequestJson: error.transportRequestJson!,
            transportResponseJson: error.transportResponseJson!,
            errorJson: error.errorJson!,
          );
          await _savedPlanRepository.refresh();
          _pendingPersistence = null;
          _setApiFailure(error);
          return;
      }
    } on Object catch (error) {
      _setPersistenceFailure(error);
    }
  }

  void discardPendingResult() {
    if (!canDiscardPendingResult) return;
    _generation++;
    _pendingPersistence = null;
    _lastRequest = null;
    _failure = null;
    _activeSession = null;
    _phase = PlanningHostPhase.setup;
    _message =
        'Unsaved evaluation result discarded. Prior durable planning state was not changed.';
    notifyListeners();
  }

  Future<void> _publishPersisted(
    Evaluation persisted,
    int generation,
    int revision,
  ) async {
    final reloaded =
        await _evaluationRepository.evaluationById(persisted.id);
    if (reloaded == null) {
      throw const FormatException(
        'Persisted evaluation could not be reloaded.',
      );
    }
    if (!_isCurrent(generation, revision)) return;
    final snapshot = _analysisSnapshot;
    if (snapshot == null ||
        reloaded.analysisSnapshotId != snapshot.id) {
      throw const FormatException(
        'Persisted evaluation no longer matches the active analysis snapshot.',
      );
    }
    _activeSession = EvaluationSession.fromEvaluationSnapshot(
      sessionId: 'session-${reloaded.id}-$generation',
      generation: generation,
      inputRevision: revision,
      analysisSnapshotId: reloaded.analysisSnapshotId,
      evaluationRequestJson: reloaded.requestJson,
      evaluationResponseJson: reloaded.responseJson,
    );
    _phase = PlanningHostPhase.decision;
    _failure = null;
    _message = null;
    _pendingPersistence = null;
    _lastRequest = null;
    notifyListeners();
  }

  Future<void> accept(
    EvaluationSession session,
    AcceptCandidateIntent intent,
  ) async {
    final active = _activeSession;
    if (!identical(active, session) ||
        active == null ||
        active.inputRevision != _inputRevision ||
        active.generation != _generation ||
        intent.sessionId != active.sessionId ||
        intent.evaluationId != active.parsedResponse.evaluationId ||
        active.parsedResponse.planning?.candidate(intent.candidateId) == null) {
      throw const SavedPlanIntegrityExceptionProxy(
        'The decision session changed before persistence.',
      );
    }
    if (_pendingAcceptance != null || _acceptanceSaving) {
      throw const AcceptancePersistenceExceptionProxy(
        'A confirmed acceptance is already waiting for local persistence.',
      );
    }

    final pending = _PendingAcceptance(
      session: session,
      intent: intent,
      generation: _generation,
      revision: _inputRevision,
    );
    _pendingAcceptance = pending;
    await _persistAcceptance(pending);
  }

  Future<void> retryAcceptancePersistence() async {
    final pending = _pendingAcceptance;
    if (pending == null ||
        _acceptanceSaving ||
        !_isCurrent(pending.generation, pending.revision) ||
        !identical(_activeSession, pending.session)) {
      return;
    }
    await _persistAcceptance(pending);
  }

  void cancelPendingAcceptance() {
    if (!canCancelPendingAcceptance) return;
    _pendingAcceptance = null;
    _failure = null;
    _message =
        'Pending acceptance save cancelled. No accepted plan was deleted or ignored.';
    notifyListeners();
  }

  Future<void> _persistAcceptance(_PendingAcceptance pending) async {
    _acceptanceSaving = true;
    _failure = null;
    _message = null;
    notifyListeners();

    try {
      await _savedPlanRepository.acceptEvaluation(
        evaluationId: pending.intent.evaluationId,
        candidateId: pending.intent.candidateId,
        selectionSource: pending.intent.selectionSource,
      );
    } on Object catch (error) {
      if (!_isCurrent(pending.generation, pending.revision) ||
          !identical(_activeSession, pending.session)) {
        _acceptanceSaving = false;
        notifyListeners();
        return;
      }
      _acceptanceSaving = false;
      _failure = PlanningHostFailure(
        code: 'LOCAL_ACCEPT_PERSISTENCE_FAILED',
        message:
            'Your acceptance is confirmed, but the local transaction did not commit. Retry the acceptance save or explicitly cancel the pending acceptance.',
        recoveryClass: RecoveryClass.noAutomaticRecovery,
        stage: 'persistence',
      );
      notifyListeners();
      throw AcceptancePersistenceExceptionProxy(error.toString());
    }

    if (!_isCurrent(pending.generation, pending.revision) ||
        !identical(_activeSession, pending.session)) {
      _acceptanceSaving = false;
      notifyListeners();
      return;
    }

    _acceptanceSaving = false;
    _pendingAcceptance = null;
    _activeSession = null;
    _phase = PlanningHostPhase.accepted;
    _message = 'Plan accepted and saved locally.';
    _failure = null;
    notifyListeners();

    final snapshot = _analysisSnapshot;
    if (snapshot != null) {
      try {
        _savedPlan = await _savedPlanRepository.planForCompetition(
          snapshot.competitionId,
        );
      } on Object {
        // The decision is already durable. A read-model reload failure must
        // not reclassify Accept as failed.
      }
    }
    try {
      _priorEvaluation =
          await _evaluationRepository.evaluationById(pending.intent.evaluationId);
    } on Object {
      // Re-evaluation can reload this persisted row on the next lifecycle.
    }
  }

  /// Leave the current Decision Report without recording a user decision.
  ///
  /// This is a presentation/host lifecycle transition only. It intentionally
  /// does not persist Ignore, Accept, or Edit Constraints semantics.
  void leaveDecision() {
    if (_phase != PlanningHostPhase.decision ||
        _activeSession == null ||
        _pendingAcceptance != null) {
      return;
    }
    _activeSession = null;
    _phase = PlanningHostPhase.setup;
    _failure = null;
    _message = null;
    notifyListeners();
  }

  void beginEditConstraints(EditConstraintsIntent intent) {
    if (_pendingAcceptance != null) return;
    final session = _activeSession;
    if (session == null ||
        intent.sessionId != session.sessionId ||
        intent.evaluationId != session.parsedResponse.evaluationId ||
        intent.inputRevision != _inputRevision) {
      return;
    }
    _phase = PlanningHostPhase.setup;
    _failure = null;
    _message = null;
    notifyListeners();
  }

  void ignore(IgnoreRecommendationIntent intent) {
    if (_pendingAcceptance != null) return;
    final session = _activeSession;
    if (session == null ||
        intent.sessionId != session.sessionId ||
        intent.evaluationId != session.parsedResponse.evaluationId ||
        intent.inputRevision != _inputRevision) {
      return;
    }
    _activeSession = null;
    _phase = PlanningHostPhase.idle;
    _failure = null;
    _message = null;
    notifyListeners();
  }

  void createFreshEvaluationBaseline() {
    if (!canCreateFreshBaseline || _pendingAcceptance != null) return;
    _forceFreshBaseline = true;
    _phase = PlanningHostPhase.setup;
    _failure = null;
    _message =
        'Fresh compatibility baseline selected. The accepted plan remains active until a new result is accepted.';
    notifyListeners();
  }

  void _mutateDraft(PlanningDraft next) {
    if (_pendingPersistence != null || _pendingAcceptance != null) {
      throw StateError(
        'Resolve pending persistence before editing constraints.',
      );
    }
    _draft = next;
    _inputRevision++;
    _activeSession = null;
    _phase = PlanningHostPhase.setup;
    _failure = null;
    _message = null;
    notifyListeners();
  }

  PlanningDraft _requireDraft() {
    final value = _draft;
    if (value == null) {
      throw StateError('Planning draft is not initialized.');
    }
    return value;
  }

  bool _isCurrent(int generation, int revision) =>
      generation == _generation && revision == _inputRevision;

  void _setApiFailure(PlanApiFailure error) {
    _phase = PlanningHostPhase.error;
    _failure = PlanningHostFailure(
      code: error.code,
      message: _publicMessage(error.code),
      recoveryClass: error.recoveryClass,
      stage: error.stage,
      statusCode: error.statusCode,
    );
    notifyListeners();
  }

  void _setLocalFailure(String code, String message) {
    _phase = PlanningHostPhase.error;
    _failure = PlanningHostFailure(
      code: code,
      message: message,
      recoveryClass: RecoveryPolicy.classify(
        FailureIdentity(
          code: code,
          stage: 'local',
          origin: FailureOrigin.local,
        ),
      ),
    );
    notifyListeners();
  }

  void _setPersistenceFailure(Object error) {
    _phase = PlanningHostPhase.persistenceError;
    final correctnessBearing =
        persistenceExitKind == PersistenceExitKind.correctnessBearing;
    _failure = PlanningHostFailure(
      code: 'LOCAL_PERSISTENCE_FAILED',
      message: correctnessBearing
          ? 'A trusted re-evaluation transition is known in this lifecycle but could not be saved locally. Retry saving before treating the prior evaluation as fresh.'
          : 'The evaluated result is safe in memory but could not be saved locally. Retry saving without calling the backend again.',
      recoveryClass: RecoveryClass.noAutomaticRecovery,
      stage: 'persistence',
    );
    notifyListeners();
  }

  static String _publicMessage(String code) {
    return switch (code) {
      'VALIDATION_ERROR' || 'PLANNING_INPUT_INVALID' =>
        'Some planning inputs are invalid. Review the setup and try again.',
      'REPORT_BUNDLE_INVALID' || 'UNSUPPORTED_REPORT_CONTRACT' =>
        'This analysis report cannot be planned safely. Refresh the analysis first.',
      'SOLVER_INDETERMINATE' =>
        'The solver could not determine a result. Retry or edit the constraints.',
      'REEVALUATION_CONTEXT_INVALID' =>
        'The prior and current planning context no longer compare safely. Reload the saved plan before trying again.',
      'UNSUPPORTED_REEVALUATION_CONTRACT' =>
        'This saved plan uses an older re-evaluation contract. A fresh baseline can be created explicitly.',
      'CLIENT_NETWORK_ERROR' ||
      'CLIENT_TIMEOUT' ||
      'CLIENT_CONNECTION_FAILED' =>
        'The planning service could not be reached. Try the request again.',
      'RESPONSE_CONTRACT_INVALID' =>
        'The planning service returned a response this app cannot use safely.',
      'LOCAL_CONTEXT_INVALID' =>
        'The local planning context is inconsistent. Reload the competition and try again.',
      'UNKNOWN_BACKEND_ERROR' =>
        'The planning service returned an unrecognized error response.',
      'AVAILABILITY_EXECUTION_FAILED' ||
      'SOLVER_EXECUTION_FAILED' ||
      'PLANNING_RUNTIME_UNAVAILABLE' ||
      'PLANNING_EXECUTION_FAILED' ||
      'EVALUATION_INVARIANT_FAILED' ||
      'INTERNAL_ERROR' =>
        'The planning service could not complete this evaluation. Try again.',
      _ => 'Planning could not be completed safely. Review the inputs or try again.',
    };
  }

  static PlanningDraft _draftFromEvaluation(Evaluation evaluation) {
    final request = _jsonObject(evaluation.requestJson, 'evaluation request');
    final readiness = _object(request['readiness_context'], 'readiness_context');
    final planning = _object(request['planning'], 'planning');
    final workload = _object(planning['workload'], 'planning.workload');
    final taskValues = workload['tasks'];
    if (taskValues is! List) {
      throw const FormatException('Persisted workload tasks are invalid.');
    }
    final availability =
        _object(planning['availability'], 'planning.availability');
    final preferenceMap =
        _object(availability['preferences'], 'planning.preferences');

    final timezone = preferenceMap['timezone'];
    final dailyLimit = preferenceMap['max_project_minutes_per_day'];
    final focus = preferenceMap['preferred_focus_minutes'];
    final buffer = preferenceMap['buffer_target_minutes'];
    if (timezone is! String ||
        dailyLimit is! int ||
        focus is! int ||
        buffer is! int) {
      throw const FormatException(
        'Persisted planning preferences are invalid.',
      );
    }

    final policy = PlanningWindowPolicyV1.fromJson(
      _jsonObject(
        evaluation.planningWindowPolicyJson,
        'planning window policy',
      ),
    );

    return PlanningDraft(
      readinessContext: ReadinessContextDraft.fromWire(readiness),
      tasks: [
        for (final value in taskValues)
          PlanningTaskDraft.fromWire(_object(value, 'workload.tasks[]')),
      ],
      preferences: PlanningPreferences(
        timezone: timezone,
        maxProjectMinutesPerDay: dailyLimit,
        preferredFocusMinutes: focus,
        bufferTargetMinutes: buffer,
        updatedAtEpochMs: evaluation.evaluatedAtEpochMs,
      ),
      windowPolicy: policy,
    );
  }

  static Map<String, dynamic> _jsonObject(String raw, String field) {
    final value = jsonDecode(raw);
    return _object(value, field);
  }

  static Map<String, dynamic> _object(Object? value, String field) {
    if (value is! Map) {
      throw FormatException('$field must be an object.');
    }
    return Map<String, dynamic>.from(value);
  }

  @override
  void dispose() {
    _apiClient.close();
    if (closeScheduleRepositoryOnDispose) {
      unawaited(_scheduleRepository.close());
    }
    if (closeEvaluationRepositoryOnDispose) {
      unawaited(_evaluationRepository.close());
    }
    if (closeSavedPlanRepositoryOnDispose) {
      unawaited(_savedPlanRepository.close());
    }
    super.dispose();
  }
}

final class SavedPlanIntegrityExceptionProxy implements Exception {
  const SavedPlanIntegrityExceptionProxy(this.message);
  final String message;

  @override
  String toString() => message;
}

final class AcceptancePersistenceExceptionProxy implements Exception {
  const AcceptancePersistenceExceptionProxy(this.message);
  final String message;

  @override
  String toString() => message;
}

sealed class _PlanRequestContext {
  const _PlanRequestContext({
    required this.generation,
    required this.revision,
    required this.snapshot,
    required this.assembly,
  });

  final int generation;
  final int revision;
  final AnalysisSnapshot snapshot;
  final PlanningAssembly assembly;
}

final class _FreshPlanRequest extends _PlanRequestContext {
  const _FreshPlanRequest({
    required super.generation,
    required super.revision,
    required super.snapshot,
    required super.assembly,
  });
}

final class _ReevaluationPlanRequest extends _PlanRequestContext {
  const _ReevaluationPlanRequest({
    required super.generation,
    required super.revision,
    required super.snapshot,
    required super.assembly,
    required this.prior,
  });

  final Evaluation prior;
}

final class _PendingAcceptance {
  const _PendingAcceptance({
    required this.session,
    required this.intent,
    required this.generation,
    required this.revision,
  });

  final EvaluationSession session;
  final AcceptCandidateIntent intent;
  final int generation;
  final int revision;
}

sealed class _PendingPersistence {
  const _PendingPersistence({
    required this.generation,
    required this.revision,
  });

  final int generation;
  final int revision;
}

final class _PendingInitial extends _PendingPersistence {
  const _PendingInitial({
    required super.generation,
    required super.revision,
    required this.snapshot,
    required this.assembly,
    required this.transport,
  });

  final AnalysisSnapshot snapshot;
  final PlanningAssembly assembly;
  final PlanEvaluateTransportResult transport;
}

final class _PendingReevaluationSuccess extends _PendingPersistence {
  const _PendingReevaluationSuccess({
    required super.generation,
    required super.revision,
    required this.snapshot,
    required this.prior,
    required this.assembly,
    required this.transport,
  });

  final AnalysisSnapshot snapshot;
  final Evaluation prior;
  final PlanningAssembly assembly;
  final PlanReevaluateTransportResult transport;
}

final class _PendingReevaluationFailure extends _PendingPersistence {
  const _PendingReevaluationFailure({
    required super.generation,
    required super.revision,
    required this.prior,
    required this.failure,
  });

  final Evaluation prior;
  final PlanApiFailure failure;
}
