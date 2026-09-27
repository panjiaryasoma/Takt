"""Product competition-analysis API routes."""

from __future__ import annotations

import json
from typing import Annotated

from fastapi import APIRouter, File, Form, Request, UploadFile
from pydantic import ValidationError

from apps.api.contracts import (
    ApiErrorResponseV1,
    CompetitionAnalyzePdfMetadataV1,
    CompetitionAnalyzeResponseV1,
    CompetitionAnalyzeUrlRequestV1,
)
from apps.api.errors import (
    ApiContractError,
    validation_contract,
    validation_details,
)
from apps.api.services.competition_analysis import (
    AnalysisContinuationError,
    AnalysisInputError,
    AnalysisInvariantError,
    AnalysisReconciliationError,
    analyze_pdf,
    analyze_url,
)
from apps.api.services.plan_evaluation import (
    ReportBundleError,
    UnsupportedReportContractError,
)
from engine.extraction import (
    MAX_SOURCE_BYTES,
    CandidateNormalizationError,
    InvalidSourceError,
    NativeExtractionError,
    OCRExtractionError,
    OCRProviderError,
    OCRProviderUnavailableError,
    OCRTimeoutError,
    SnapshotBatchError,
    SnapshotIntegrityError,
    SourceFetchError,
    SourceLimitExceededError,
    UnsupportedMediaTypeError,
)

router = APIRouter(tags=["competitions"])

_ANALYSIS_ERROR_RESPONSES = {
    400: {"model": ApiErrorResponseV1},
    413: {"model": ApiErrorResponseV1},
    415: {"model": ApiErrorResponseV1},
    422: {"model": ApiErrorResponseV1},
    500: {"model": ApiErrorResponseV1},
    502: {"model": ApiErrorResponseV1},
    503: {"model": ApiErrorResponseV1},
    504: {"model": ApiErrorResponseV1},
}


def _raise_analysis_error(exc: Exception) -> None:
    if isinstance(exc, AnalysisInputError):
        raise ApiContractError(
            status_code=422,
            code="SOURCE_METADATA_INVALID",
            message="Source metadata validation failed.",
            stage="ingestion",
        ) from exc
    if isinstance(exc, AnalysisContinuationError):
        raise ApiContractError(
            status_code=422,
            code="ANALYSIS_CONTEXT_INVALID",
            message="Previous report and source analysis context are inconsistent.",
            stage="analysis",
        ) from exc
    if isinstance(exc, UnsupportedReportContractError):
        raise ApiContractError(
            status_code=422,
            code="UNSUPPORTED_REPORT_CONTRACT",
            message="Canonical report contract or policy version is not supported.",
            stage="report",
        ) from exc
    if isinstance(exc, ReportBundleError):
        raise ApiContractError(
            status_code=422,
            code="REPORT_BUNDLE_INVALID",
            message="Canonical report bundle failed integrity validation.",
            stage="report",
        ) from exc
    if isinstance(exc, InvalidSourceError):
        raise ApiContractError(
            status_code=400,
            code="INVALID_SOURCE",
            message="Source reference is invalid or not allowed.",
            stage="ingestion",
        ) from exc
    if isinstance(exc, SourceFetchError):
        raise ApiContractError(
            status_code=502,
            code="SOURCE_FETCH_FAILED",
            message="Source could not be retrieved.",
            stage="ingestion",
        ) from exc
    if isinstance(exc, SourceLimitExceededError):
        raise ApiContractError(
            status_code=413,
            code="SOURCE_LIMIT_EXCEEDED",
            message="Source exceeds the supported ingestion limit.",
            stage="ingestion",
        ) from exc
    if isinstance(exc, UnsupportedMediaTypeError):
        raise ApiContractError(
            status_code=415,
            code="UNSUPPORTED_MEDIA_TYPE",
            message="Source media type is not supported.",
            stage="ingestion",
        ) from exc
    if isinstance(exc, OCRProviderUnavailableError):
        raise ApiContractError(
            status_code=503,
            code="OCR_PROVIDER_UNAVAILABLE",
            message="OCR provider is unavailable.",
            stage="extraction",
        ) from exc
    if isinstance(exc, OCRTimeoutError):
        raise ApiContractError(
            status_code=504,
            code="OCR_TIMEOUT",
            message="OCR exceeded the configured execution time.",
            stage="extraction",
        ) from exc
    if isinstance(exc, OCRProviderError):
        raise ApiContractError(
            status_code=502,
            code="OCR_PROVIDER_ERROR",
            message="OCR provider failed.",
            stage="extraction",
        ) from exc
    if isinstance(exc, NativeExtractionError):
        raise ApiContractError(
            status_code=422,
            code="NATIVE_EXTRACTION_FAILED",
            message="Source content could not be processed by native extraction.",
            stage="extraction",
        ) from exc
    if isinstance(exc, OCRExtractionError):
        raise ApiContractError(
            status_code=422,
            code="OCR_EXTRACTION_FAILED",
            message="Source content could not be processed by OCR extraction.",
            stage="extraction",
        ) from exc
    if isinstance(exc, CandidateNormalizationError):
        raise ApiContractError(
            status_code=500,
            code="CANDIDATE_NORMALIZATION_FAILED",
            message="Extraction output could not be normalized safely.",
            stage="extraction",
        ) from exc
    if isinstance(exc, SnapshotIntegrityError):
        raise ApiContractError(
            status_code=500,
            code="SNAPSHOT_INTEGRITY_FAILED",
            message="Source snapshot integrity validation failed.",
            stage="extraction",
        ) from exc
    if isinstance(exc, SnapshotBatchError):
        raise ApiContractError(
            status_code=500,
            code="SNAPSHOT_BATCH_INVALID",
            message="Source extraction paths produced an inconsistent snapshot batch.",
            stage="extraction",
        ) from exc
    if isinstance(exc, AnalysisReconciliationError):
        raise ApiContractError(
            status_code=500,
            code="RECONCILIATION_FAILED",
            message="Server-produced extraction material could not be reconciled.",
            stage="reconciliation",
        ) from exc
    if isinstance(exc, AnalysisInvariantError):
        raise ApiContractError(
            status_code=500,
            code="ANALYSIS_INVARIANT_FAILED",
            message="Analysis output lost required traceability.",
            stage="analysis",
        ) from exc
    raise exc


@router.post(
    "/competitions/analyze/url",
    response_model=CompetitionAnalyzeResponseV1,
    responses=_ANALYSIS_ERROR_RESPONSES,
)
def analyze_url_route(
    request: CompetitionAnalyzeUrlRequestV1,
) -> CompetitionAnalyzeResponseV1:
    try:
        return analyze_url(request)
    except Exception as exc:
        _raise_analysis_error(exc)
        raise


@router.post(
    "/competitions/analyze/pdf",
    response_model=CompetitionAnalyzeResponseV1,
    responses=_ANALYSIS_ERROR_RESPONSES,
)
async def analyze_pdf_route(
    request: Request,
    metadata: Annotated[str, Form(...)],
    file: Annotated[UploadFile, File(...)],
) -> CompetitionAnalyzeResponseV1:
    form = await request.form()
    field_names = [name for name, _value in form.multi_items()]
    if len(field_names) != 2 or set(field_names) != {"metadata", "file"}:
        raise ApiContractError(
            status_code=422,
            code="VALIDATION_ERROR",
            message="PDF analysis requires exactly metadata and file form fields.",
            stage="validation",
        )

    metadata_raw = metadata
    upload = file
    if upload.content_type not in {None, "application/pdf"}:
        raise ApiContractError(
            status_code=415,
            code="UNSUPPORTED_MEDIA_TYPE",
            message="PDF analysis accepts application/pdf uploads only.",
            stage="ingestion",
        )

    try:
        decoded = json.loads(metadata_raw)
        metadata = CompetitionAnalyzePdfMetadataV1.model_validate(decoded)
    except (json.JSONDecodeError, ValidationError) as exc:
        errors = tuple(exc.errors()) if isinstance(exc, ValidationError) else ()
        code, message, stage = validation_contract(
            errors,
            request_path="/api/v1/competitions/analyze/pdf",
        )
        raise ApiContractError(
            status_code=422,
            code=code,
            message=message,
            stage=stage,
            details=validation_details(errors),
        ) from exc

    content = await upload.read(MAX_SOURCE_BYTES + 1)
    try:
        return analyze_pdf(metadata, content)
    except Exception as exc:
        _raise_analysis_error(exc)
        raise
