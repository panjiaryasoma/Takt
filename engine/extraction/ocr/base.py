"""Replaceable OCR provider boundary."""

from __future__ import annotations

from typing import Protocol

from engine.extraction.ocr.models import OCRTextBlock


class OCRProvider(Protocol):
    """Provider contract for page-image OCR.

    Implementations receive one rasterized page at a time and must return
    observations only. They do not assign competition field semantics and do
    not produce canonical facts.
    """

    @property
    def provider_id(self) -> str: ...

    @property
    def provider_version(self) -> str: ...

    def extract_page(
        self,
        image_bytes: bytes,
        *,
        page_number: int,
        timeout_seconds: float,
    ) -> tuple[OCRTextBlock, ...]: ...
