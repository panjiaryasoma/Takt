"""Internal OCR observation models for the visual extraction path."""

from __future__ import annotations

from dataclasses import dataclass

from packages.contracts import SourceRecord


@dataclass(frozen=True, slots=True)
class OCRTextBlock:
    """One OCR text line with page-level provenance."""

    locator: str
    text: str
    page_number: int
    confidence: float | None = None
    bounding_box: tuple[int, int, int, int] | None = None


@dataclass(frozen=True, slots=True)
class OCRDocument:
    """OCR observations for one source before semantic field extraction."""

    source_record: SourceRecord
    provider_id: str
    provider_version: str
    blocks: tuple[OCRTextBlock, ...]
    page_count: int
    pages_without_ocr_text: tuple[int, ...] = ()
    render_dpi: int = 150
    extractor_fingerprint: str = ""

    @property
    def text(self) -> str:
        """Flatten OCR blocks for consumers that do not need locators."""

        return "\n".join(block.text for block in self.blocks)

    @property
    def has_ocr_text(self) -> bool:
        """Whether the OCR path observed at least one non-empty text block."""

        return bool(self.blocks)
