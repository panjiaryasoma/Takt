"""Source ingestion and candidate extraction adapters.

Block 2 exposes native HTML/PDF ingestion only. No native extractor output is
canonical, and OCR/reconciliation stay behind later block boundaries.
"""

from engine.extraction.errors import (
    IngestionError,
    InvalidSourceError,
    NativeExtractionError,
    SourceFetchError,
    SourceLimitExceededError,
    UnsupportedMediaTypeError,
)
from engine.extraction.models import (
    NativeDocument,
    NativeTextBlock,
    RetrievalMetadata,
    SourceContext,
)
from engine.extraction.native import (
    MAX_EXTRACTED_TEXT_CHARS,
    MAX_NATIVE_BLOCKS,
    MAX_PDF_PAGES,
    MAX_SOURCE_BYTES,
    ingest_pdf_native,
    ingest_url_native,
)

__all__ = [
    "MAX_EXTRACTED_TEXT_CHARS",
    "MAX_NATIVE_BLOCKS",
    "MAX_PDF_PAGES",
    "MAX_SOURCE_BYTES",
    "IngestionError",
    "InvalidSourceError",
    "NativeDocument",
    "NativeExtractionError",
    "NativeTextBlock",
    "RetrievalMetadata",
    "SourceContext",
    "SourceFetchError",
    "SourceLimitExceededError",
    "UnsupportedMediaTypeError",
    "ingest_pdf_native",
    "ingest_url_native",
]
