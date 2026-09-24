"""OCR service for rasterized PDF pages.

Native and OCR extraction remain independent observation paths. This module
never treats OCR output as canonical and does not perform semantic field
normalization or reconciliation.
"""

from __future__ import annotations

import json
from hashlib import sha256
from hmac import compare_digest
from math import ceil
from time import monotonic

import pymupdf

from engine.extraction.errors import (
    IngestionError,
    OCRExtractionError,
    OCRTimeoutError,
    SourceLimitExceededError,
)
from engine.extraction.ocr.base import OCRProvider
from engine.extraction.ocr.models import OCRDocument, OCRTextBlock
from engine.extraction.ocr.tesseract import TesseractOCRProvider
from packages.contracts import SourceRecord

MAX_OCR_SOURCE_BYTES = 20 * 1024 * 1024
MAX_OCR_PAGES = 50
OCR_RENDER_DPI = 150
MAX_OCR_IMAGE_PIXELS = 16_000_000
OCR_TIMEOUT_SECONDS = 20.0
OCR_TOTAL_TIMEOUT_SECONDS = 120.0
MAX_OCR_BLOCKS = 20_000
MAX_OCR_TEXT_CHARS = 5_000_000


def _provider_extractor_fingerprint(
    provider: OCRProvider,
    *,
    provider_id: str,
    provider_version: str,
    render_dpi: int,
) -> str:
    material = {
        "provider_id": provider_id,
        "provider_version": provider_version,
        "language": getattr(provider, "language", None),
        "page_segmentation_mode": getattr(provider, "page_segmentation_mode", None),
        "render_dpi": render_dpi,
    }
    encoded = json.dumps(
        material,
        sort_keys=True,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    return f"ocr-xfp-{sha256(encoded).hexdigest()}"


def _validate_limits(
    *,
    max_source_bytes: int,
    max_pages: int,
    render_dpi: int,
    max_image_pixels: int,
    timeout_seconds: float,
    total_timeout_seconds: float,
    max_blocks: int,
    max_text_chars: int,
) -> None:
    if (
        max_source_bytes <= 0
        or max_pages <= 0
        or render_dpi <= 0
        or max_image_pixels <= 0
        or timeout_seconds <= 0
        or total_timeout_seconds <= 0
        or max_blocks <= 0
        or max_text_chars <= 0
    ):
        raise OCRExtractionError("OCR resource limits must be greater than zero")



def _verify_source_content_hash(
    content: bytes,
    *,
    source_record: SourceRecord,
) -> None:
    expected = source_record.content_hash.strip().lower()
    prefix = "sha256:"
    if not expected.startswith(prefix):
        raise OCRExtractionError(
            "OCR source content hash cannot be verified; expected sha256:<hex>",
            source_ref=source_record.url_or_document_id,
        )

    expected_digest = expected[len(prefix) :]
    if len(expected_digest) != 64:
        raise OCRExtractionError(
            "OCR source content hash is not a valid SHA-256 digest",
            source_ref=source_record.url_or_document_id,
        )
    try:
        int(expected_digest, 16)
    except ValueError as exc:
        raise OCRExtractionError(
            "OCR source content hash is not a valid SHA-256 digest",
            source_ref=source_record.url_or_document_id,
        ) from exc

    actual = sha256(content).hexdigest()
    if not compare_digest(actual, expected_digest):
        raise OCRExtractionError(
            "OCR source bytes do not match SourceRecord content_hash",
            source_ref=source_record.url_or_document_id,
        )

def _page_pixel_count(page: pymupdf.Page, *, render_dpi: int) -> int:
    scale = render_dpi / 72.0
    width = ceil(page.rect.width * scale)
    height = ceil(page.rect.height * scale)
    return width * height


def _remaining_timeout(*, deadline: float, per_page_timeout: float) -> float:
    remaining = deadline - monotonic()
    if remaining <= 0:
        raise OCRTimeoutError("OCR document exceeded total timeout budget")
    return min(per_page_timeout, remaining)


def ocr_pdf(
    content: bytes,
    *,
    source_record: SourceRecord,
    provider: OCRProvider | None = None,
    max_source_bytes: int = MAX_OCR_SOURCE_BYTES,
    max_pages: int = MAX_OCR_PAGES,
    render_dpi: int = OCR_RENDER_DPI,
    max_image_pixels: int = MAX_OCR_IMAGE_PIXELS,
    timeout_seconds: float = OCR_TIMEOUT_SECONDS,
    total_timeout_seconds: float = OCR_TOTAL_TIMEOUT_SECONDS,
    max_blocks: int = MAX_OCR_BLOCKS,
    max_text_chars: int = MAX_OCR_TEXT_CHARS,
) -> OCRDocument:
    """Rasterize a PDF and run an independent OCR observation path."""

    _validate_limits(
        max_source_bytes=max_source_bytes,
        max_pages=max_pages,
        render_dpi=render_dpi,
        max_image_pixels=max_image_pixels,
        timeout_seconds=timeout_seconds,
        total_timeout_seconds=total_timeout_seconds,
        max_blocks=max_blocks,
        max_text_chars=max_text_chars,
    )
    if not isinstance(source_record, SourceRecord):
        raise OCRExtractionError("source_record must be a SourceRecord")
    if not isinstance(content, bytes):
        raise OCRExtractionError("OCR PDF content must be bytes")
    if len(content) > max_source_bytes:
        raise SourceLimitExceededError(
            f"OCR source exceeded byte limit of {max_source_bytes}",
            source_ref=source_record.url_or_document_id,
        )

    _verify_source_content_hash(content, source_record=source_record)

    active_provider = (
        provider if provider is not None else TesseractOCRProvider()
    )
    provider_id = getattr(active_provider, "provider_id", None)
    provider_version = getattr(active_provider, "provider_version", None)
    if not isinstance(provider_id, str) or not provider_id.strip():
        raise OCRExtractionError("OCR provider_id must be a non-empty string")
    if not isinstance(provider_version, str) or not provider_version.strip():
        raise OCRExtractionError("OCR provider_version must be a non-empty string")
    extractor_fingerprint = _provider_extractor_fingerprint(
        active_provider,
        provider_id=provider_id,
        provider_version=provider_version,
        render_dpi=render_dpi,
    )

    try:
        document = pymupdf.open(stream=content, filetype="pdf")
    except Exception as exc:  # PyMuPDF exception classes vary by version.
        raise OCRExtractionError(
            "PDF could not be opened for OCR",
            source_ref=source_record.url_or_document_id,
        ) from exc

    deadline = monotonic() + total_timeout_seconds
    blocks: list[OCRTextBlock] = []
    pages_without_text: list[int] = []
    extracted_text_chars = 0
    seen_locators: set[str] = set()

    try:
        if document.needs_pass:
            raise OCRExtractionError(
                "encrypted/password-protected PDF cannot be OCR processed",
                source_ref=source_record.url_or_document_id,
            )

        if document.page_count > max_pages:
            raise SourceLimitExceededError(
                f"OCR source exceeded page limit of {max_pages}",
                source_ref=source_record.url_or_document_id,
            )

        scale = render_dpi / 72.0
        matrix = pymupdf.Matrix(scale, scale)
        for page_index in range(document.page_count):
            page_number = page_index + 1
            _remaining_timeout(deadline=deadline, per_page_timeout=timeout_seconds)
            page = document.load_page(page_index)
            pixel_count = _page_pixel_count(page, render_dpi=render_dpi)
            if pixel_count > max_image_pixels:
                raise SourceLimitExceededError(
                    f"OCR page {page_number} exceeded pixel limit of {max_image_pixels}",
                    source_ref=source_record.url_or_document_id,
                )

            try:
                pixmap = page.get_pixmap(
                    matrix=matrix,
                    colorspace=pymupdf.csRGB,
                    alpha=False,
                )
                image_bytes = pixmap.tobytes("png")
            except Exception as exc:
                raise OCRExtractionError(
                    f"PDF page {page_number} could not be rasterized for OCR",
                    source_ref=source_record.url_or_document_id,
                ) from exc

            page_timeout = _remaining_timeout(
                deadline=deadline,
                per_page_timeout=timeout_seconds,
            )
            try:
                page_blocks = active_provider.extract_page(
                    image_bytes,
                    page_number=page_number,
                    timeout_seconds=page_timeout,
                )
            except IngestionError:
                raise
            except Exception as exc:
                raise OCRExtractionError(
                    f"OCR provider failed on page {page_number}",
                    source_ref=source_record.url_or_document_id,
                ) from exc
            if not isinstance(page_blocks, tuple):
                raise OCRExtractionError(
                    "OCR provider must return tuple[OCRTextBlock, ...]",
                    source_ref=source_record.url_or_document_id,
                )
            if not page_blocks:
                pages_without_text.append(page_number)
                continue

            for block in page_blocks:
                if not isinstance(block, OCRTextBlock):
                    raise OCRExtractionError(
                        "OCR provider returned an invalid block type",
                        source_ref=source_record.url_or_document_id,
                    )
                if block.page_number != page_number:
                    raise OCRExtractionError(
                        "OCR provider returned a block for the wrong page",
                        source_ref=source_record.url_or_document_id,
                    )
                if not block.locator.strip() or not block.text.strip():
                    raise OCRExtractionError(
                        "OCR provider returned an empty locator or text block",
                        source_ref=source_record.url_or_document_id,
                    )
                if block.locator in seen_locators:
                    raise OCRExtractionError(
                        "OCR provider returned duplicate locators",
                        source_ref=source_record.url_or_document_id,
                    )
                if block.confidence is not None and not 0 <= block.confidence <= 1:
                    raise OCRExtractionError(
                        "OCR provider confidence must be between 0 and 1",
                        source_ref=source_record.url_or_document_id,
                    )
                if block.bounding_box is not None:
                    left, top, right, bottom = block.bounding_box
                    if left < 0 or top < 0 or right < left or bottom < top:
                        raise OCRExtractionError(
                            "OCR provider returned an invalid bounding box",
                            source_ref=source_record.url_or_document_id,
                        )
                if len(blocks) >= max_blocks:
                    raise SourceLimitExceededError(
                        f"OCR exceeded block limit of {max_blocks}",
                        source_ref=source_record.url_or_document_id,
                    )
                extracted_text_chars += len(block.text)
                if extracted_text_chars > max_text_chars:
                    raise SourceLimitExceededError(
                        f"OCR exceeded extracted text limit of {max_text_chars}",
                        source_ref=source_record.url_or_document_id,
                    )
                seen_locators.add(block.locator)
                blocks.append(block)

        return OCRDocument(
            source_record=source_record,
            provider_id=provider_id,
            provider_version=provider_version,
            blocks=tuple(blocks),
            page_count=document.page_count,
            pages_without_ocr_text=tuple(pages_without_text),
            render_dpi=render_dpi,
            extractor_fingerprint=extractor_fingerprint,
        )
    except IngestionError:
        raise
    except Exception as exc:
        raise OCRExtractionError(
            "PDF could not be processed safely for OCR",
            source_ref=source_record.url_or_document_id,
        ) from exc
    finally:
        try:
            document.close()
        except Exception:
            pass
