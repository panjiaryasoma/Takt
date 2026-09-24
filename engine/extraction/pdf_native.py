"""Native PDF extraction with PyMuPDF.

This module intentionally does not invoke OCR. Pages without selectable text
are recorded as observability metadata. That signal does not mean OCR should
run only on empty pages: Block 3 remains an independent extraction path.
"""

from __future__ import annotations

import pymupdf

from engine.extraction.errors import NativeExtractionError, SourceLimitExceededError
from engine.extraction.models import NativeDocument, NativeTextBlock, RetrievalMetadata
from packages.contracts import SourceRecord


def _clean_pdf_text(value: str) -> str:
    return " ".join(value.split())


def extract_pdf_native(
    content: bytes,
    *,
    source_record: SourceRecord,
    retrieval: RetrievalMetadata | None = None,
    max_pages: int = 250,
    max_blocks: int = 20_000,
    max_text_chars: int = 5_000_000,
) -> NativeDocument:
    """Extract selectable PDF text while retaining page/block provenance."""

    if max_pages <= 0 or max_blocks <= 0 or max_text_chars <= 0:
        raise NativeExtractionError(
            "PDF native extraction limits must be greater than zero",
            source_ref=source_record.url_or_document_id,
        )

    try:
        document = pymupdf.open(stream=content, filetype="pdf")
    except Exception as exc:  # PyMuPDF exception classes vary by version.
        raise NativeExtractionError(
            "PDF could not be opened by the native extractor",
            source_ref=source_record.url_or_document_id,
        ) from exc

    blocks: list[NativeTextBlock] = []
    pages_without_text: list[int] = []
    extracted_text_chars = 0

    try:
        if document.page_count > max_pages:
            raise SourceLimitExceededError(
                f"PDF exceeded page limit of {max_pages}",
                source_ref=source_record.url_or_document_id,
            )

        for page_index in range(document.page_count):
            page_number = page_index + 1
            page = document.load_page(page_index)
            page_has_text = False
            for raw_block in page.get_text("blocks", sort=True):
                if len(raw_block) < 7:
                    continue
                x0, y0, x1, y1, raw_text, block_number, block_type = raw_block[:7]
                if block_type != 0:
                    continue
                text = _clean_pdf_text(str(raw_text))
                if not text:
                    continue
                if len(blocks) >= max_blocks:
                    raise SourceLimitExceededError(
                        f"native PDF exceeded block limit of {max_blocks}",
                        source_ref=source_record.url_or_document_id,
                    )
                extracted_text_chars += len(text)
                if extracted_text_chars > max_text_chars:
                    raise SourceLimitExceededError(
                        f"native PDF exceeded extracted text limit of {max_text_chars}",
                        source_ref=source_record.url_or_document_id,
                    )
                page_has_text = True
                blocks.append(
                    NativeTextBlock(
                        locator=f"page:{page_number}:block:{block_number}",
                        text=text,
                        kind="pdf_text",
                        page_number=page_number,
                        bounding_box=(float(x0), float(y0), float(x1), float(y1)),
                    )
                )
            if not page_has_text:
                pages_without_text.append(page_number)

        return NativeDocument(
            source_record=source_record,
            media_type="application/pdf",
            raw_size_bytes=len(content),
            blocks=tuple(blocks),
            page_count=document.page_count,
            pages_without_native_text=tuple(pages_without_text),
            retrieval=retrieval,
        )
    except SourceLimitExceededError:
        raise
    except NativeExtractionError:
        raise
    except Exception as exc:
        raise NativeExtractionError(
            "PDF native text extraction failed",
            source_ref=source_record.url_or_document_id,
        ) from exc
    finally:
        document.close()
