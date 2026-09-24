"""Explicit failure types for native and OCR source extraction.

Engine boundaries normalize raw library/process failures into stable error
types instead of leaking implementation-specific exceptions.
"""

from __future__ import annotations


class IngestionError(RuntimeError):
    """Base error for source ingestion and extraction."""

    code = "INGESTION_ERROR"

    def __init__(self, message: str, *, source_ref: str | None = None) -> None:
        super().__init__(message)
        self.source_ref = source_ref


class InvalidSourceError(IngestionError):
    """Raised before retrieval when the source reference is not allowed."""

    code = "INVALID_SOURCE"


class SourceFetchError(IngestionError):
    """Raised when an HTTP(S) source cannot be retrieved successfully."""

    code = "SOURCE_FETCH_FAILED"


class SourceLimitExceededError(IngestionError):
    """Raised when a source exceeds an explicit ingestion resource bound."""

    code = "SOURCE_LIMIT_EXCEEDED"


class UnsupportedMediaTypeError(IngestionError):
    """Raised when a retrieved source is neither supported HTML nor PDF."""

    code = "UNSUPPORTED_MEDIA_TYPE"


class NativeExtractionError(IngestionError):
    """Raised when supported content cannot be parsed natively."""

    code = "NATIVE_EXTRACTION_FAILED"


class OCRProviderError(IngestionError):
    """Base error for OCR provider failures."""

    code = "OCR_PROVIDER_ERROR"


class OCRProviderUnavailableError(OCRProviderError):
    """Raised when the configured OCR provider cannot be executed."""

    code = "OCR_PROVIDER_UNAVAILABLE"


class OCRTimeoutError(IngestionError):
    """Raised when OCR exceeds a configured page or document time budget."""

    code = "OCR_TIMEOUT"


class OCRExtractionError(IngestionError):
    """Raised when OCR input/rendering/output cannot be processed safely."""

    code = "OCR_EXTRACTION_FAILED"


class CandidateNormalizationError(IngestionError):
    """Raised when an extraction observation violates candidate-report boundaries."""

    code = "CANDIDATE_NORMALIZATION_FAILED"
