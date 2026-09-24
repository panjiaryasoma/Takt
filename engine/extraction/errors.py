"""Explicit failure types for source ingestion.

Block 2 must fail clearly on invalid/broken sources instead of leaking raw
library exceptions through the engine boundary.
"""

from __future__ import annotations


class IngestionError(RuntimeError):
    """Base error for native source ingestion."""

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
