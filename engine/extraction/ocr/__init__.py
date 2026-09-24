"""Replaceable OCR extraction path."""

from engine.extraction.ocr.base import OCRProvider
from engine.extraction.ocr.models import OCRDocument, OCRTextBlock
from engine.extraction.ocr.service import (
    MAX_OCR_BLOCKS,
    MAX_OCR_IMAGE_PIXELS,
    MAX_OCR_PAGES,
    MAX_OCR_SOURCE_BYTES,
    MAX_OCR_TEXT_CHARS,
    OCR_RENDER_DPI,
    OCR_TIMEOUT_SECONDS,
    OCR_TOTAL_TIMEOUT_SECONDS,
    ocr_pdf,
)
from engine.extraction.ocr.tesseract import TesseractOCRProvider

__all__ = [
    "MAX_OCR_BLOCKS",
    "MAX_OCR_IMAGE_PIXELS",
    "MAX_OCR_PAGES",
    "MAX_OCR_SOURCE_BYTES",
    "MAX_OCR_TEXT_CHARS",
    "OCR_RENDER_DPI",
    "OCR_TIMEOUT_SECONDS",
    "OCR_TOTAL_TIMEOUT_SECONDS",
    "OCRDocument",
    "OCRProvider",
    "OCRTextBlock",
    "TesseractOCRProvider",
    "ocr_pdf",
]
