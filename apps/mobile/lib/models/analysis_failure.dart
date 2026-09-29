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
          'Analisis gagal dengan respons yang belum dikenali aplikasi.',
      retryable: _retryableCodes.contains(code),
    );
  }

  factory AnalysisFailure.network(Object error) => AnalysisFailure(
        code: 'NETWORK_ERROR',
        stage: 'transport',
        message: error.toString(),
        userMessage: 'Tidak dapat terhubung ke server Takt.',
        retryable: true,
      );

  factory AnalysisFailure.contract(Object error) => AnalysisFailure(
        code: 'RESPONSE_CONTRACT_INVALID',
        stage: 'response',
        message: error.toString(),
        userMessage: 'Respons server tidak cocok dengan kontrak aplikasi.',
        retryable: false,
      );

  factory AnalysisFailure.persistence(Object error) => AnalysisFailure(
        code: 'LOCAL_PERSISTENCE_FAILED',
        stage: 'persistence',
        message: error.toString(),
        userMessage:
            'Hasil analisis sudah diterima, tetapi gagal disimpan di perangkat.',
        retryable: true,
      );

  static const _retryableCodes = <String>{
    'SOURCE_FETCH_FAILED',
    'OCR_PROVIDER_UNAVAILABLE',
    'OCR_TIMEOUT',
    'OCR_PROVIDER_ERROR',
  };

  static const _knownMessages = <String, String>{
    'VALIDATION_ERROR': 'Data permintaan belum valid.',
    'SOURCE_METADATA_INVALID': 'Metadata sumber belum valid.',
    'ANALYSIS_CONTEXT_INVALID':
        'Konteks analisis sebelumnya tidak lagi cocok.',
    'UNSUPPORTED_REPORT_CONTRACT':
        'Versi laporan tidak didukung aplikasi ini.',
    'REPORT_BUNDLE_INVALID':
        'Laporan lokal gagal pemeriksaan integritas.',
    'INVALID_SOURCE': 'Sumber tidak valid atau tidak diizinkan.',
    'SOURCE_FETCH_FAILED': 'Sumber gagal diambil dari jaringan.',
    'SOURCE_LIMIT_EXCEEDED':
        'Ukuran sumber melewati batas yang didukung.',
    'UNSUPPORTED_MEDIA_TYPE': 'Format sumber tidak didukung.',
    'OCR_PROVIDER_UNAVAILABLE':
        'Layanan OCR sedang tidak tersedia.',
    'OCR_TIMEOUT': 'Proses OCR melewati batas waktu.',
    'OCR_PROVIDER_ERROR':
        'Layanan OCR gagal memproses dokumen.',
    'NATIVE_EXTRACTION_FAILED':
        'Konten sumber gagal diproses secara langsung.',
    'OCR_EXTRACTION_FAILED':
        'OCR tidak menghasilkan ekstraksi yang valid.',
    'CANDIDATE_NORMALIZATION_FAILED':
        'Hasil ekstraksi gagal dinormalisasi dengan aman.',
    'SNAPSHOT_INTEGRITY_FAILED':
        'Integritas snapshot sumber gagal diverifikasi.',
    'SNAPSHOT_BATCH_INVALID':
        'Hasil ekstraksi sumber tidak konsisten.',
    'RECONCILIATION_FAILED':
        'Server gagal membangun laporan canonical.',
    'ANALYSIS_INVARIANT_FAILED':
        'Hasil analisis kehilangan traceability yang diwajibkan.',
    'INTERNAL_ERROR':
        'Server tidak dapat menyelesaikan analisis.',
  };

  @override
  String toString() => 'AnalysisFailure($code, $stage): $message';
}
