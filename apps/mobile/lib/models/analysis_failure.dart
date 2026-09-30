import 'recovery_policy.dart';

class AnalysisFailure implements Exception {
  const AnalysisFailure({
    required this.code,
    required this.stage,
    required this.message,
    required this.userMessage,
    this.statusCode,
    this.origin = FailureOrigin.backend,
    bool? retryable,
  });

  final String code;
  final String stage;
  final String message;
  final String userMessage;
  final int? statusCode;
  final FailureOrigin origin;

  FailureIdentity get identity => FailureIdentity(
        code: code,
        stage: stage,
        statusCode: statusCode,
        origin: origin,
      );

  RecoveryClass get recoveryClass => RecoveryPolicy.classify(identity);

  /// Compatibility projection only. RecoveryClass is the authority.
  bool get retryable => recoveryClass == RecoveryClass.retrySameInput;

  factory AnalysisFailure.fromBackend({
    required String code,
    required String stage,
    required String message,
    required int statusCode,
  }) {
    return AnalysisFailure(
      code: code,
      stage: stage,
      message: message,
      statusCode: statusCode,
      origin: FailureOrigin.backend,
      userMessage: _knownMessages[code] ??
          'Analysis failed with a response this app does not recognize.',
    );
  }

  factory AnalysisFailure.timeout(Object error) => AnalysisFailure(
        code: 'CLIENT_TIMEOUT',
        stage: 'transport',
        message: error.toString(),
        userMessage: 'The connection to the Takt server timed out.',
        origin: FailureOrigin.clientTransport,
      );

  factory AnalysisFailure.connection(Object error) => AnalysisFailure(
        code: 'CLIENT_CONNECTION_FAILED',
        stage: 'transport',
        message: error.toString(),
        userMessage: 'Could not connect to the Takt server.',
        origin: FailureOrigin.clientTransport,
      );

  factory AnalysisFailure.network(Object error) => AnalysisFailure(
        code: 'CLIENT_NETWORK_ERROR',
        stage: 'transport',
        message: error.toString(),
        userMessage: 'Could not connect to the Takt server.',
        origin: FailureOrigin.clientTransport,
      );

  factory AnalysisFailure.contract(Object error) => AnalysisFailure(
        code: 'RESPONSE_CONTRACT_INVALID',
        stage: 'response',
        message: error.toString(),
        userMessage: 'The server response does not match the app contract.',
        origin: FailureOrigin.local,
      );

  factory AnalysisFailure.localContext(Object error, {bool readFailed = false}) =>
      AnalysisFailure(
        code: readFailed ? 'LOCAL_CONTEXT_READ_FAILED' : 'LOCAL_CONTEXT_INVALID',
        stage: 'local_context',
        message: error.toString(),
        userMessage: 'The saved analysis context could not be loaded on this device. Reload it or start a new analysis.',
        origin: FailureOrigin.local,
      );

  factory AnalysisFailure.persistence(Object error) => AnalysisFailure(
        code: 'LOCAL_PERSISTENCE_FAILED',
        stage: 'persistence',
        message: error.toString(),
        userMessage:
            'The analysis result was received, but could not be saved on this device.',
        origin: FailureOrigin.local,
      );

  static const _knownMessages = <String, String>{
    'VALIDATION_ERROR': 'The request data is invalid.',
    'SOURCE_METADATA_INVALID': 'The source metadata is invalid.',
    'ANALYSIS_CONTEXT_INVALID':
        'The previous analysis context is no longer compatible.',
    'UNSUPPORTED_REPORT_CONTRACT':
        'This report version is not supported by the app.',
    'REPORT_BUNDLE_INVALID':
        'The local report failed its integrity check.',
    'INVALID_SOURCE': 'The source is invalid or not allowed.',
    'SOURCE_FETCH_FAILED': 'The source could not be fetched from the network.',
    'SOURCE_LIMIT_EXCEEDED':
        'The source exceeds the supported size limit.',
    'UNSUPPORTED_MEDIA_TYPE': 'The source format is not supported.',
    'OCR_PROVIDER_UNAVAILABLE':
        'The OCR service is currently unavailable.',
    'OCR_TIMEOUT': 'The OCR process timed out.',
    'OCR_PROVIDER_ERROR':
        'The OCR service failed to process the document.',
    'NATIVE_EXTRACTION_FAILED':
        'The source content could not be processed directly.',
    'OCR_EXTRACTION_FAILED':
        'OCR did not produce a valid extraction.',
    'CANDIDATE_NORMALIZATION_FAILED':
        'The extracted result could not be normalized safely.',
    'SNAPSHOT_INTEGRITY_FAILED':
        'The source snapshot failed integrity verification.',
    'SNAPSHOT_BATCH_INVALID':
        'The source extraction results are inconsistent.',
    'RECONCILIATION_FAILED':
        'The server failed to build the canonical report.',
    'ANALYSIS_INVARIANT_FAILED':
        'The analysis result is missing required traceability.',
    'INTERNAL_ERROR':
        'The server could not complete the analysis.',
  };

  @override
  String toString() => 'AnalysisFailure($code, $stage): $message';
}
