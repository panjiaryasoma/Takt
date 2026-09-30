enum FailureOrigin {
  backend,
  clientTransport,
  clientValidation,
  local,
}

enum RecoveryClass {
  fixInput,
  retrySameInput,
  reuploadSource,
  editConstraints,
  reevaluate,
  reloadContext,
  noAutomaticRecovery,
}

enum RecoveryAction {
  retryRequest,
  editSource,
  replaceSource,
  editConstraints,
  reevaluate,
  reloadContext,
  startNewAnalysis,
  retryLocalSave,
  discardUnsavedResult,
  retryAcceptanceSave,
  cancelPendingAcceptance,
  back,
}

enum PersistenceExitKind {
  discardableResult,
  correctnessBearing,
  acceptanceIntent,
}

final class FailureIdentity {
  const FailureIdentity({
    required this.code,
    required this.stage,
    required this.origin,
    this.statusCode,
  });

  final String code;
  final String stage;
  final FailureOrigin origin;
  final int? statusCode;
}

final class RecoveryDescriptor {
  const RecoveryDescriptor({
    required this.title,
    required this.message,
    required this.recoveryClass,
    required this.technicalCode,
    required this.stage,
    this.primaryAction,
    this.secondaryAction,
  });

  final String title;
  final String message;
  final RecoveryClass recoveryClass;
  final String technicalCode;
  final String stage;
  final RecoveryAction? primaryAction;
  final RecoveryAction? secondaryAction;
}

/// 6B presentation-side mapper.
///
/// This is intentionally explicit rather than status-code inference. The
/// 6A JSON recovery policy is the parity authority, joined to the 5A public
/// error matrix by the cross-language test. Unknown failures fail closed.
abstract final class RecoveryPolicy {
  static RecoveryClass classify(FailureIdentity failure) {
    return switch (failure.origin) {
      FailureOrigin.clientTransport => _clientTransport(failure.code),
      FailureOrigin.clientValidation => _clientValidation(failure.code),
      FailureOrigin.local => _local(failure.code),
      FailureOrigin.backend => _backend(failure.code),
    };
  }

  static bool canRetrySameInput(FailureIdentity failure) =>
      classify(failure) == RecoveryClass.retrySameInput;

  static RecoveryClass _clientTransport(String code) => switch (code) {
        'CLIENT_NETWORK_ERROR' ||
        'CLIENT_TIMEOUT' ||
        'CLIENT_CONNECTION_FAILED' =>
          RecoveryClass.retrySameInput,
        _ => RecoveryClass.noAutomaticRecovery,
      };

  static RecoveryClass _clientValidation(String code) => switch (code) {
        'CLIENT_VALIDATION_ERROR' => RecoveryClass.fixInput,
        'CLIENT_SOURCE_LIMIT' || 'CLIENT_MEDIA_TYPE' =>
          RecoveryClass.reuploadSource,
        _ => RecoveryClass.noAutomaticRecovery,
      };

  static RecoveryClass _local(String code) => switch (code) {
        'LOCAL_CONTEXT_MISSING' || 'LOCAL_CONTEXT_INVALID' ||
        'LOCAL_CONTEXT_READ_FAILED' =>
          RecoveryClass.reloadContext,
        'LOCAL_PERSISTENCE_FAILED' ||
        'LOCAL_ACCEPT_PERSISTENCE_FAILED' ||
        'RESPONSE_CONTRACT_INVALID' =>
          RecoveryClass.noAutomaticRecovery,
        _ => RecoveryClass.noAutomaticRecovery,
      };

  static RecoveryClass _backend(String code) => switch (code) {
        'VALIDATION_ERROR' || 'SOURCE_METADATA_INVALID' ||
        'SOURCE_LIMIT_EXCEEDED' || 'PLANNING_INPUT_INVALID' =>
          RecoveryClass.fixInput,
        'INVALID_SOURCE' => RecoveryClass.fixInput,
        'SOURCE_FETCH_FAILED' ||
        'OCR_PROVIDER_UNAVAILABLE' ||
        'OCR_TIMEOUT' ||
        'OCR_PROVIDER_ERROR' =>
          RecoveryClass.retrySameInput,
        'UNSUPPORTED_MEDIA_TYPE' ||
        'NATIVE_EXTRACTION_FAILED' ||
        'OCR_EXTRACTION_FAILED' =>
          RecoveryClass.reuploadSource,
        'SOLVER_INDETERMINATE' => RecoveryClass.editConstraints,
        'AVAILABILITY_EXECUTION_FAILED' ||
        'SOLVER_EXECUTION_FAILED' ||
        'PLANNING_RUNTIME_UNAVAILABLE' =>
          RecoveryClass.retrySameInput,
        'ANALYSIS_CONTEXT_INVALID' || 'REEVALUATION_CONTEXT_INVALID' ||
        'REPORT_BUNDLE_INVALID' =>
          RecoveryClass.reloadContext,
        'UNSUPPORTED_REPORT_CONTRACT' ||
        'UNSUPPORTED_REEVALUATION_CONTRACT' ||
        'PLANNING_EXECUTION_FAILED' || 'EVALUATION_INVARIANT_FAILED' ||
        'CANDIDATE_NORMALIZATION_FAILED' ||
        'SNAPSHOT_INTEGRITY_FAILED' ||
        'SNAPSHOT_BATCH_INVALID' ||
        'RECONCILIATION_FAILED' ||
        'ANALYSIS_INVARIANT_FAILED' ||
        'INTERNAL_ERROR' ||
        'UNKNOWN_BACKEND_ERROR' =>
          RecoveryClass.noAutomaticRecovery,
        _ => RecoveryClass.noAutomaticRecovery,
      };
}
