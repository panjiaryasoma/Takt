import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../data/remote/competition_api_client.dart';
import '../data/repositories/analysis_repository.dart';
import '../models/analysis_failure.dart';
import '../models/analysis_snapshot.dart';
import '../models/analysis_source_draft.dart';
import '../models/analysis_step.dart';
import '../models/competition_analysis_wire.dart';
import '../models/recovery_policy.dart';
import '../utils/source_identity.dart';

typedef _RequestCommand = Future<CompetitionAnalysisTransportResult> Function();

final class AnalysisOperationIdentity {
  const AnalysisOperationIdentity({
    required this.generation,
    required this.competitionId,
    required this.sourceIdentity,
    required this.continuationContextIdentity,
  });

  final int generation;
  final String competitionId;
  final String sourceIdentity;
  final String continuationContextIdentity;
}

final class AnalisisViewModel extends ChangeNotifier {
  AnalisisViewModel({
    required CompetitionApiClient apiClient,
    required AnalysisRepository repository,
    this.closeRepositoryOnDispose = true,
  })  : _apiClient = apiClient,
        _repository = repository;

  final CompetitionApiClient _apiClient;
  final AnalysisRepository _repository;
  final bool closeRepositoryOnDispose;

  AnalysisPhase _phase = AnalysisPhase.idle;
  String? _competitionId;
  CompetitionAnalyzeResponseWire? _response;
  AnalysisSnapshot? _activeSnapshot;
  String? _originalBody;
  AnalysisFailure? _failure;
  _PendingAnalysisPersistence? _pendingPersistence;
  _AnalysisRequest? _lastRequest;
  AnalysisOperationIdentity? _operation;
  AnalysisSourceDraft? _sourceDraft;
  int _generation = 0;

  AnalysisPhase get phase => _phase;
  String? get competitionId => _competitionId;
  CompetitionAnalyzeResponseWire? get response => _response;
  AnalysisSnapshot? get activeSnapshot => _activeSnapshot;
  String? get originalBody => _originalBody;
  AnalysisFailure? get failure => _failure;
  AnalysisSourceDraft? get sourceDraft => _sourceDraft;
  AnalysisOperationIdentity? get operationIdentity => _operation;
  int get generation => _generation;

  bool get busy =>
      _phase == AnalysisPhase.validating ||
      _phase == AnalysisPhase.submitting ||
      _phase == AnalysisPhase.persisting;

  bool get selesai => _phase == AnalysisPhase.ready;

  bool get canRetryRequest =>
      _phase == AnalysisPhase.requestError &&
      _failure?.recoveryClass == RecoveryClass.retrySameInput &&
      _lastRequest != null &&
      _operation != null &&
      _isCurrent(_operation!);

  bool get canRetryPersistence =>
      _phase == AnalysisPhase.persistenceError &&
      _pendingPersistence != null &&
      _isCurrent(_pendingPersistence!.identity);

  bool get canDiscardUnsavedResult => canRetryPersistence;

  bool get requiresFreshAnalysis {
    final code = _failure?.code;
    return code == 'ANALYSIS_CONTEXT_INVALID' ||
        code == 'REPORT_BUNDLE_INVALID' ||
        code == 'UNSUPPORTED_REPORT_CONTRACT' ||
        code == 'LOCAL_CONTEXT_MISSING' ||
        code == 'LOCAL_CONTEXT_INVALID';
  }

  bool get hasCurrentCompetition =>
      _competitionId != null && _response != null;

  String get statusText {
    switch (_phase) {
      case AnalysisPhase.idle:
        return 'Waiting for a competition source.';
      case AnalysisPhase.validating:
        return 'Preparing the source and analysis context.';
      case AnalysisPhase.submitting:
        return 'The backend is processing the source.';
      case AnalysisPhase.persisting:
        return 'Saving the analysis result on this device.';
      case AnalysisPhase.ready:
        return 'Result saved and ready for review.';
      case AnalysisPhase.requestError:
      case AnalysisPhase.persistenceError:
        return _failure?.userMessage ?? 'Analysis failed.';
    }
  }

  List<AnalysisStep> get steps {
    AnalysisStepState stateFor(int index) {
      final completed = switch (_phase) {
        AnalysisPhase.idle => -1,
        AnalysisPhase.validating => -1,
        AnalysisPhase.submitting => 0,
        AnalysisPhase.persisting => 1,
        AnalysisPhase.ready => 3,
        AnalysisPhase.requestError => 0,
        AnalysisPhase.persistenceError => 1,
      };
      if (index <= completed) return AnalysisStepState.done;

      final active = switch (_phase) {
        AnalysisPhase.validating => 0,
        AnalysisPhase.submitting => 1,
        AnalysisPhase.persisting => 2,
        AnalysisPhase.ready => -1,
        AnalysisPhase.requestError => -1,
        AnalysisPhase.persistenceError => -1,
        AnalysisPhase.idle => -1,
      };
      if (index == active) return AnalysisStepState.process;
      return AnalysisStepState.waiting;
    }

    return [
      AnalysisStep(
        title: 'Preparing source',
        detail: 'Validating source input and metadata',
        state: stateFor(0),
      ),
      AnalysisStep(
        title: 'Processing on the backend',
        detail: 'Extraction and reconciliation are running on the server',
        state: stateFor(1),
      ),
      AnalysisStep(
        title: 'Saving local result',
        detail: 'Raw response is saved without reconstruction',
        state: stateFor(2),
      ),
      AnalysisStep(
        title: 'Ready for review',
        detail: 'Canonical report and provenance are available',
        state: stateFor(3),
      ),
    ];
  }

  void ensureSourceDraft({required bool continuation}) {
    final current = _sourceDraft;
    if (current != null && current.continuation == continuation) return;
    _sourceDraft = AnalysisSourceDraft(
      mode: AnalysisSourceMode.pdf,
      continuation: continuation,
    );
  }

  void updateSourceDraft(AnalysisSourceDraft draft) {
    if (busy) return;
    _sourceDraft = draft;
  }

  void beginSourceEdit() {
    if (_phase == AnalysisPhase.persisting) return;
    _invalidateOperation();
    _failure = null;
    _phase = _response == null ? AnalysisPhase.idle : AnalysisPhase.ready;
    notifyListeners();
  }

  Future<void> analyzeUrl({
    required String url,
    required SourceTypeWire sourceType,
    required bool continuation,
  }) async {
    if (busy) return;
    _phase = AnalysisPhase.validating;
    _failure = null;
    notifyListeners();

    try {
      final competitionId = continuation
          ? _requireCompetitionId()
          : _newCompetitionId();
      final continuationMaterial = continuation
          ? await _continuationMaterial(competitionId)
          : null;
      final source = AnalysisSourceMetadata(
        sourceId: SourceIdentity.urlSourceId(url),
        sourceType: sourceType,
      );
      final identity = AnalysisOperationIdentity(
        generation: ++_generation,
        competitionId: competitionId,
        sourceIdentity: source.sourceId,
        continuationContextIdentity:
            continuationMaterial?.snapshotId ?? 'fresh-analysis',
      );
      final request = _AnalysisRequest(
        identity: identity,
        command: () => _apiClient.analyzeUrl(
          competitionId: competitionId,
          url: url,
          source: source,
          continuation: continuationMaterial?.context,
        ),
      );
      _operation = identity;
      _lastRequest = request;
      await _executeRequest(request);
    } on AnalysisFailure catch (error) {
      _setRequestFailure(error);
    } on Object catch (error) {
      _setRequestFailure(AnalysisFailure.contract(error));
    }
  }

  Future<void> analyzePdf({
    required String filename,
    required Uint8List bytes,
    required SourceTypeWire sourceType,
    required bool continuation,
  }) async {
    if (busy) return;
    _phase = AnalysisPhase.validating;
    _failure = null;
    notifyListeners();

    try {
      final competitionId = continuation
          ? _requireCompetitionId()
          : _newCompetitionId();
      final continuationMaterial = continuation
          ? await _continuationMaterial(competitionId)
          : null;
      final source = AnalysisSourceMetadata(
        sourceId: SourceIdentity.pdfSourceId(bytes),
        sourceType: sourceType,
      );
      final documentId = SourceIdentity.pdfDocumentId(filename, bytes);
      final identity = AnalysisOperationIdentity(
        generation: ++_generation,
        competitionId: competitionId,
        sourceIdentity: source.sourceId,
        continuationContextIdentity:
            continuationMaterial?.snapshotId ?? 'fresh-analysis',
      );
      final request = _AnalysisRequest(
        identity: identity,
        command: () => _apiClient.analyzePdf(
          competitionId: competitionId,
          documentId: documentId,
          filename: filename,
          bytes: bytes,
          source: source,
          continuation: continuationMaterial?.context,
        ),
      );
      _operation = identity;
      _lastRequest = request;
      await _executeRequest(request);
    } on AnalysisFailure catch (error) {
      _setRequestFailure(error);
    } on Object catch (error) {
      _setRequestFailure(AnalysisFailure.contract(error));
    }
  }

  Future<void> retryRequest() async {
    final request = _lastRequest;
    if (!canRetryRequest || request == null) return;
    await _executeRequest(request);
  }

  Future<void> retryPersistence() async {
    final pending = _pendingPersistence;
    if (!canRetryPersistence || pending == null) return;

    _phase = AnalysisPhase.persisting;
    _failure = null;
    notifyListeners();
    try {
      final snapshot = await _repository.persistResponse(
        originalBody: pending.result.originalBody,
        response: pending.result.response,
      );
      if (!_isCurrent(pending.identity)) return;
      _acceptPersisted(pending.result, snapshot, pending.identity);
    } on Object catch (error) {
      if (!_isCurrent(pending.identity)) return;
      _phase = AnalysisPhase.persistenceError;
      _failure = AnalysisFailure.persistence(error);
      notifyListeners();
    }
  }

  void discardUnsavedResult() {
    final pending = _pendingPersistence;
    if (!canDiscardUnsavedResult || pending == null) return;
    _generation++;
    _operation = null;
    _pendingPersistence = null;
    _lastRequest = null;
    _failure = null;
    _phase = _response == null ? AnalysisPhase.idle : AnalysisPhase.ready;
    notifyListeners();
  }

  Future<AnalysisSnapshot?> latestSnapshotForCompetition(
    String competitionId,
  ) {
    return _repository.latestSnapshot(competitionId);
  }

  Future<void> loadSnapshot(AnalysisSnapshot snapshot) async {
    _generation++;
    _operation = null;
    _pendingPersistence = null;
    _lastRequest = null;
    try {
      final parsed =
          CompetitionAnalyzeResponseWire.parse(snapshot.responseJson);
      _competitionId = snapshot.competitionId;
      _response = parsed;
      _activeSnapshot = snapshot;
      _originalBody = snapshot.responseJson;
      _sourceDraft = null;
      _failure = null;
      _phase = AnalysisPhase.ready;
      notifyListeners();
    } on Object catch (error) {
      _phase = AnalysisPhase.requestError;
      _failure = AnalysisFailure.contract(error);
      notifyListeners();
    }
  }

  void resetForNewCompetition() {
    if (_phase == AnalysisPhase.persisting) return;
    _generation++;
    _phase = AnalysisPhase.idle;
    _competitionId = null;
    _response = null;
    _activeSnapshot = null;
    _originalBody = null;
    _failure = null;
    _pendingPersistence = null;
    _lastRequest = null;
    _operation = null;
    _sourceDraft = null;
    notifyListeners();
  }

  Future<void> _executeRequest(_AnalysisRequest request) async {
    if (!_isCurrent(request.identity)) return;

    _phase = AnalysisPhase.submitting;
    _failure = null;
    _pendingPersistence = null;
    notifyListeners();

    try {
      final result = await request.command();
      if (!_isCurrent(request.identity)) return;

      _phase = AnalysisPhase.persisting;
      _pendingPersistence = _PendingAnalysisPersistence(
        identity: request.identity,
        result: result,
      );
      notifyListeners();

      try {
        final snapshot = await _repository.persistResponse(
          originalBody: result.originalBody,
          response: result.response,
        );
        if (!_isCurrent(request.identity)) return;
        _acceptPersisted(result, snapshot, request.identity);
      } on Object catch (error) {
        if (!_isCurrent(request.identity)) return;
        _phase = AnalysisPhase.persistenceError;
        _failure = AnalysisFailure.persistence(error);
        notifyListeners();
      }
    } on AnalysisFailure catch (error) {
      if (!_isCurrent(request.identity)) return;
      _setRequestFailure(error);
    } on Object catch (error) {
      if (!_isCurrent(request.identity)) return;
      _setRequestFailure(AnalysisFailure.contract(error));
    }
  }

  void _acceptPersisted(
    CompetitionAnalysisTransportResult result,
    AnalysisSnapshot snapshot,
    AnalysisOperationIdentity identity,
  ) {
    if (!_isCurrent(identity)) return;
    _competitionId = result.response.report.competitionId;
    _response = result.response;
    _activeSnapshot = snapshot;
    _originalBody = result.originalBody;
    _pendingPersistence = null;
    _lastRequest = null;
    _operation = null;
    _sourceDraft = null;
    _failure = null;
    _phase = AnalysisPhase.ready;
    notifyListeners();
  }

  void _setRequestFailure(AnalysisFailure error) {
    _phase = AnalysisPhase.requestError;
    _failure = error;
    _pendingPersistence = null;
    notifyListeners();
  }

  Future<_ContinuationMaterial> _continuationMaterial(
    String competitionId,
  ) async {
    final snapshot = await _repository.latestSnapshot(competitionId);
    if (snapshot == null) {
      throw const AnalysisFailure(
        code: 'LOCAL_CONTEXT_MISSING',
        stage: 'continuation',
        message: 'No cached snapshot exists for continuation.',
        userMessage:
            'The previous source context is unavailable. Start a new analysis.',
        origin: FailureOrigin.local,
      );
    }
    try {
      return _ContinuationMaterial(
        snapshotId: snapshot.id,
        context: AnalysisContinuationContext.fromOriginalBody(
          snapshot.responseJson,
        ),
      );
    } on Object catch (error) {
      throw AnalysisFailure(
        code: 'LOCAL_CONTEXT_INVALID',
        stage: 'continuation',
        message: 'Cached continuation response is invalid: $error',
        userMessage:
            'The previous source context is corrupted. Start a new analysis.',
        origin: FailureOrigin.local,
      );
    }
  }

  String _requireCompetitionId() {
    final id = _competitionId;
    if (id == null) {
      throw const AnalysisFailure(
        code: 'LOCAL_CONTEXT_MISSING',
        stage: 'continuation',
        message: 'No active competition identity exists.',
        userMessage:
            'The previous competition context is unavailable. Start a new analysis.',
        origin: FailureOrigin.local,
      );
    }
    return id;
  }

  String _newCompetitionId() {
    return 'cmp-${DateTime.now().microsecondsSinceEpoch}';
  }

  bool _isCurrent(AnalysisOperationIdentity identity) =>
      identical(_operation, identity) && identity.generation == _generation;

  void _invalidateOperation() {
    _generation++;
    _operation = null;
    _lastRequest = null;
    _pendingPersistence = null;
  }

  @override
  void dispose() {
    _apiClient.close();
    if (closeRepositoryOnDispose) {
      unawaited(_repository.close());
    }
    super.dispose();
  }
}

final class _AnalysisRequest {
  const _AnalysisRequest({
    required this.identity,
    required this.command,
  });

  final AnalysisOperationIdentity identity;
  final _RequestCommand command;
}

final class _PendingAnalysisPersistence {
  const _PendingAnalysisPersistence({
    required this.identity,
    required this.result,
  });

  final AnalysisOperationIdentity identity;
  final CompetitionAnalysisTransportResult result;
}

final class _ContinuationMaterial {
  const _ContinuationMaterial({
    required this.snapshotId,
    required this.context,
  });

  final String snapshotId;
  final AnalysisContinuationContext context;
}
