"""5A public API error-contract freeze.

Every row freezes endpoint, failure class, HTTP status, public code/stage,
public detail shape, and re-evaluation transition semantics. The matrix is data
on purpose so tests cannot silently redefine the contract case by case.
"""

from __future__ import annotations

from dataclasses import dataclass

DETAIL_ARRAY = "array<ApiErrorDetailV1>"
TRANSITION_NA = "N/A"
TRANSITION_NULL = "NULL"
TRANSITION_PASSTHROUGH = "PASSTHROUGH_TRUSTED_WITNESS"


@dataclass(frozen=True, slots=True)
class PublicErrorCase:
    endpoint: str
    failure_class: str
    http_status: int
    code: str
    stage: str
    details_shape: str = DETAIL_ARRAY
    transition: str = TRANSITION_NA


ANALYSIS_ENDPOINTS = (
    "POST /api/v1/competitions/analyze/url",
    "POST /api/v1/competitions/analyze/pdf",
)

_ANALYSIS_FAILURES = (
    ("AnalysisInputError", 422, "SOURCE_METADATA_INVALID", "ingestion"),
    ("AnalysisContinuationError", 422, "ANALYSIS_CONTEXT_INVALID", "analysis"),
    ("UnsupportedReportContractError", 422, "UNSUPPORTED_REPORT_CONTRACT", "report"),
    ("ReportBundleError", 422, "REPORT_BUNDLE_INVALID", "report"),
    ("InvalidSourceError", 400, "INVALID_SOURCE", "ingestion"),
    ("SourceFetchError", 502, "SOURCE_FETCH_FAILED", "ingestion"),
    ("SourceLimitExceededError", 413, "SOURCE_LIMIT_EXCEEDED", "ingestion"),
    ("UnsupportedMediaTypeError", 415, "UNSUPPORTED_MEDIA_TYPE", "ingestion"),
    ("OCRProviderUnavailableError", 503, "OCR_PROVIDER_UNAVAILABLE", "extraction"),
    ("OCRTimeoutError", 504, "OCR_TIMEOUT", "extraction"),
    ("OCRProviderError", 502, "OCR_PROVIDER_ERROR", "extraction"),
    ("NativeExtractionError", 422, "NATIVE_EXTRACTION_FAILED", "extraction"),
    ("OCRExtractionError", 422, "OCR_EXTRACTION_FAILED", "extraction"),
    ("CandidateNormalizationError", 500, "CANDIDATE_NORMALIZATION_FAILED", "extraction"),
    ("SnapshotIntegrityError", 500, "SNAPSHOT_INTEGRITY_FAILED", "extraction"),
    ("SnapshotBatchError", 500, "SNAPSHOT_BATCH_INVALID", "extraction"),
    ("AnalysisReconciliationError", 500, "RECONCILIATION_FAILED", "reconciliation"),
    ("AnalysisInvariantError", 500, "ANALYSIS_INVARIANT_FAILED", "analysis"),
    ("UnhandledException", 500, "INTERNAL_ERROR", "internal"),
)

PLAN_FAILURES = (
    ("UnsupportedReportContractError", 422, "UNSUPPORTED_REPORT_CONTRACT", "report"),
    ("ReportBundleError", 422, "REPORT_BUNDLE_INVALID", "report"),
    ("PlanEvaluationInputError", 422, "PLANNING_INPUT_INVALID", "evaluation"),
    ("PlanEvaluationIndeterminateError", 503, "SOLVER_INDETERMINATE", "solver"),
    ("PlanEvaluationAvailabilityError", 500, "AVAILABILITY_EXECUTION_FAILED", "availability"),
    ("PlanEvaluationSolverExecutionError", 500, "SOLVER_EXECUTION_FAILED", "solver"),
    ("PlanEvaluationRuntimeError", 500, "PLANNING_RUNTIME_UNAVAILABLE", "planning"),
    ("PlanEvaluationExecutionError", 500, "PLANNING_EXECUTION_FAILED", "planning"),
    ("PlanEvaluationInvariantError", 500, "EVALUATION_INVARIANT_FAILED", "evaluation"),
    ("UnhandledException", 500, "INTERNAL_ERROR", "internal"),
)

PUBLIC_ERROR_MATRIX = (
    *(
        PublicErrorCase(endpoint, failure, status, code, stage)
        for endpoint in ANALYSIS_ENDPOINTS
        for failure, status, code, stage in _ANALYSIS_FAILURES
    ),
    *(
        PublicErrorCase("POST /api/v1/plans/evaluate", failure, status, code, stage)
        for failure, status, code, stage in PLAN_FAILURES
    ),
    PublicErrorCase(
        "POST /api/v1/plans/re-evaluate",
        "ReevaluationContextInvalid",
        409,
        "REEVALUATION_CONTEXT_INVALID",
        "reevaluation",
        transition=TRANSITION_NULL,
    ),
    *(
        PublicErrorCase(
            "POST /api/v1/plans/re-evaluate",
            f"ReevaluationExecutionFailure[{failure}]",
            status,
            code,
            stage,
            transition=TRANSITION_PASSTHROUGH,
        )
        for failure, status, code, stage in PLAN_FAILURES
        if failure != "UnhandledException"
    ),
    PublicErrorCase(
        "POST /api/v1/plans/re-evaluate",
        "UnhandledException",
        500,
        "INTERNAL_ERROR",
        "internal",
        transition=TRANSITION_NULL,
    ),
    PublicErrorCase(
        "POST /api/v1/plans/re-evaluate",
        "RequestValidationError",
        422,
        "VALIDATION_ERROR",
        "validation",
        transition=TRANSITION_NULL,
    ),
    PublicErrorCase(
        "POST /api/v1/plans/re-evaluate",
        "UnsupportedReevaluationContract",
        422,
        "UNSUPPORTED_REEVALUATION_CONTRACT",
        "reevaluation",
        transition=TRANSITION_NULL,
    ),
)

HEALTH_CONTRACT = ("GET /health", 200, {"status": "ok"})
