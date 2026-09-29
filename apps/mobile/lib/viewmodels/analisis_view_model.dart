import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/remote/competition_api_client.dart';
import '../data/repositories/analysis_repository.dart';
import '../models/analysis_failure.dart';
import '../models/analysis_snapshot.dart';
import '../models/analysis_step.dart';
import '../models/competition_analysis_wire.dart';
import '../utils/source_identity.dart';

typedef _RequestCommand = Future<CompetitionAnalysisTransportResult> Function();

class AnalisisViewModel extends ChangeNotifier {
  AnalisisViewModel({
    required CompetitionApiClient apiClient,
    required AnalysisRepository repository,
  })  : _apiClient = apiClient,
        _repository = repository;

  final CompetitionApiClient _apiClient;
  final AnalysisRepository _repository;

  AnalysisPhase _phase = AnalysisPhase.idle;
  String? _competitionId;
  CompetitionAnalyzeResponseWire? _response;
  AnalysisSnapshot? _activeSnapshot;
  String? _originalBody;
  AnalysisFailure? _failure;
  CompetitionAnalysisTransportResult? _pendingPersistence;
  _RequestCommand? _lastRequest;

  AnalysisPhase get phase => _phase;
  String? get competitionId => _competitionId;
  CompetitionAnalyzeResponseWire? get response => _response;
  AnalysisSnapshot? get activeSnapshot => _activeSnapshot;
  String? get originalBody => _originalBody;
  AnalysisFailure? get failure => _failure;

  bool get busy =>
      _phase == AnalysisPhase.validating ||
      _phase == AnalysisPhase.submitting ||
      _phase == AnalysisPhase.persisting;

  bool get selesai => _phase == AnalysisPhase.ready;

  bool get canRetryRequest =>
      _phase == AnalysisPhase.requestError &&
      _failure?.retryable == true &&
      _lastRequest != null;

  bool get canRetryPersistence =>
      _phase == AnalysisPhase.persistenceError &&
      _pendingPersistence != null;

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
      final context = continuation
          ? await _continuationContext(competitionId)
          : null;
      final source = AnalysisSourceMetadata(
        sourceId: SourceIdentity.urlSourceId(url),
        sourceType: sourceType,
      );

      _competitionId = competitionId;
      _lastRequest = () => _apiClient.analyzeUrl(
            competitionId: competitionId,
            url: url,
            source: source,
            continuation: context,
          );
      await _executeRequest();
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
      final context = continuation
          ? await _continuationContext(competitionId)
          : null;
      final source = AnalysisSourceMetadata(
        sourceId: SourceIdentity.pdfSourceId(bytes),
        sourceType: sourceType,
      );
      final documentId = SourceIdentity.pdfDocumentId(filename, bytes);

      _competitionId = competitionId;
      _lastRequest = () => _apiClient.analyzePdf(
            competitionId: competitionId,
            documentId: documentId,
            filename: filename,
            bytes: bytes,
            source: source,
            continuation: context,
          );
      await _executeRequest();
    } on AnalysisFailure catch (error) {
      _setRequestFailure(error);
    } on Object catch (error) {
      _setRequestFailure(AnalysisFailure.contract(error));
    }
  }

  Future<void> retryRequest() async {
    if (!canRetryRequest) return;
    await _executeRequest();
  }

  Future<void> retryPersistence() async {
    final pending = _pendingPersistence;
    if (!canRetryPersistence || pending == null) return;

    _phase = AnalysisPhase.persisting;
    _failure = null;
    notifyListeners();
    try {
      final snapshot = await _repository.persistResponse(
        originalBody: pending.originalBody,
        response: pending.response,
      );
      _acceptPersisted(pending, snapshot);
    } on Object catch (error) {
      _phase = AnalysisPhase.persistenceError;
      _failure = AnalysisFailure.persistence(error);
      notifyListeners();
    }
  }

  Future<AnalysisSnapshot?> latestSnapshotForCompetition(
    String competitionId,
  ) {
    return _repository.latestSnapshot(competitionId);
  }

  Future<void> loadSnapshot(AnalysisSnapshot snapshot) async {
    try {
      final parsed =
          CompetitionAnalyzeResponseWire.parse(snapshot.responseJson);
      _competitionId = snapshot.competitionId;
      _response = parsed;
      _activeSnapshot = snapshot;
      _originalBody = snapshot.responseJson;
      _pendingPersistence = null;
      _lastRequest = null;
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
    if (busy) return;
    _phase = AnalysisPhase.idle;
    _competitionId = null;
    _response = null;
    _activeSnapshot = null;
    _originalBody = null;
    _failure = null;
    _pendingPersistence = null;
    _lastRequest = null;
    notifyListeners();
  }

  Future<void> _executeRequest() async {
    final command = _lastRequest;
    if (command == null) return;

    _phase = AnalysisPhase.submitting;
    _failure = null;
    _pendingPersistence = null;
    notifyListeners();

    try {
      final result = await command();
      _phase = AnalysisPhase.persisting;
      _pendingPersistence = result;
      notifyListeners();

      try {
        final snapshot = await _repository.persistResponse(
          originalBody: result.originalBody,
          response: result.response,
        );
        _acceptPersisted(result, snapshot);
      } on Object catch (error) {
        _response = result.response;
        _originalBody = result.originalBody;
        _phase = AnalysisPhase.persistenceError;
        _failure = AnalysisFailure.persistence(error);
        notifyListeners();
      }
    } on AnalysisFailure catch (error) {
      _setRequestFailure(error);
    } on Object catch (error) {
      _setRequestFailure(AnalysisFailure.contract(error));
    }
  }

  void _acceptPersisted(
    CompetitionAnalysisTransportResult result,
    AnalysisSnapshot snapshot,
  ) {
    _competitionId = result.response.report.competitionId;
    _response = result.response;
    _activeSnapshot = snapshot;
    _originalBody = result.originalBody;
    _pendingPersistence = null;
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

  Future<AnalysisContinuationContext> _continuationContext(
    String competitionId,
  ) async {
    final snapshot =
        await _repository.latestSnapshot(competitionId);
    if (snapshot == null) {
      throw const AnalysisFailure(
        code: 'LOCAL_CONTEXT_MISSING',
        stage: 'continuation',
        message: 'No cached snapshot exists for continuation.',
        userMessage:
            'The previous source context is unavailable. Start a new analysis.',
        retryable: false,
      );
    }
    try {
      return AnalysisContinuationContext.fromOriginalBody(
        snapshot.responseJson,
      );
    } on Object catch (error) {
      throw AnalysisFailure(
        code: 'LOCAL_CONTEXT_INVALID',
        stage: 'continuation',
        message: 'Cached continuation response is invalid: $error',
        userMessage:
            'The previous source context is corrupted. Start a new analysis.',
        retryable: false,
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
        retryable: false,
      );
    }
    return id;
  }

  String _newCompetitionId() {
    return 'cmp-${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _apiClient.close();
    unawaited(_repository.close());
    super.dispose();
  }
}