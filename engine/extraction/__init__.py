"""Source ingestion and independent native/OCR observation paths.

Extractor output is evidence-oriented only. Semantic candidate normalization
and reconciliation remain separate downstream boundaries.
"""

from engine.extraction.candidate_bridge import (
    CandidateReportNormalizer,
    ExtractionDocument,
    normalize_candidate_report,
)
from engine.extraction.candidate_normalizer import (
    CANDIDATE_NORMALIZER_VERSION,
    RuleBasedCandidateNormalizer,
)
from engine.extraction.errors import (
    CandidateNormalizationError,
    IngestionError,
    InvalidSourceError,
    NativeExtractionError,
    OCRExtractionError,
    OCRProviderError,
    OCRProviderUnavailableError,
    OCRTimeoutError,
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
from engine.extraction.ocr import (
    MAX_OCR_BLOCKS,
    MAX_OCR_IMAGE_PIXELS,
    MAX_OCR_PAGES,
    MAX_OCR_SOURCE_BYTES,
    MAX_OCR_TEXT_CHARS,
    OCR_RENDER_DPI,
    OCR_TIMEOUT_SECONDS,
    OCR_TOTAL_TIMEOUT_SECONDS,
    OCRDocument,
    OCRProvider,
    OCRTextBlock,
    TesseractOCRProvider,
    ocr_pdf,
)

__all__ = [
    "CANDIDATE_NORMALIZER_VERSION",
    "MAX_EXTRACTED_TEXT_CHARS",
    "MAX_NATIVE_BLOCKS",
    "MAX_OCR_BLOCKS",
    "MAX_OCR_IMAGE_PIXELS",
    "MAX_OCR_PAGES",
    "MAX_OCR_SOURCE_BYTES",
    "MAX_OCR_TEXT_CHARS",
    "MAX_PDF_PAGES",
    "MAX_SOURCE_BYTES",
    "OCR_RENDER_DPI",
    "OCR_TIMEOUT_SECONDS",
    "OCR_TOTAL_TIMEOUT_SECONDS",
    "CandidateNormalizationError",
    "CandidateReportNormalizer",
    "ExtractionDocument",
    "IngestionError",
    "InvalidSourceError",
    "NativeDocument",
    "NativeExtractionError",
    "NativeTextBlock",
    "OCRDocument",
    "OCRExtractionError",
    "OCRProvider",
    "OCRProviderError",
    "OCRProviderUnavailableError",
    "OCRTextBlock",
    "OCRTimeoutError",
    "RetrievalMetadata",
    "RuleBasedCandidateNormalizer",
    "SourceContext",
    "SourceFetchError",
    "SourceLimitExceededError",
    "TesseractOCRProvider",
    "UnsupportedMediaTypeError",
    "ingest_pdf_native",
    "ingest_url_native",
    "normalize_candidate_report",
    "ocr_pdf",
]
