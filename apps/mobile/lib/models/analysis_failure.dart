class AnalysisFailure implements Exception {
  const AnalysisFailure({
    required this.code,
    required this.stage,
    required this.message,
    required this.userMessage,
    required this.retryable,
  });

  final String code;
  final String stage;
  final String message;
  final String userMessage;
  final bool retryable;

  factory AnalysisFailure.fromBackend({
    required String code,
    required String stage,
    required String message,
  }) {
    return AnalysisFailure(
      code: code,
      stage: stage,
      message: message,
      userMessage: _knownMessages[code] ??
          'Analysis failed with a response this app does not recognize.',
      retryable: _retryableCodes.contains(code),
    );
  }

  factory AnalysisFailure.network(Object error) => AnalysisFailure(
        code: 'NETWORK_ERROR',
        stage: 'transport',
        message: error.toString(),
        userMessage: 'Could not connect to the Takt server.',
        retryable: true,
      );

  factory AnalysisFailure.contract(Object error) => AnalysisFailure(
        code: 'RESPONSE_CONTRACT_INVALID',
        stage: 'response',
        message: error.toString(),
        userMessage: 'The server response does not match the app contract.',
        retryable: false,
      );

  factory AnalysisFailure.persistence(Object error) => AnalysisFailure(
        code: 'LOCAL_PERSISTENCE_FAILED',
        stage: 'persistence',
        message: error.toString(),
        userMessage:
            'The analysis result was received, but could not be saved on this device.',
        retryable: true,
      );

  static const _retryableCodes = <String>{
    'SOURCE_FETCH_FAILED',
    'OCR_PROVIDER_UNAVAILABLE',
    'OCR_TIMEOUT',
    'OCR_PROVIDER_ERROR',
  };

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