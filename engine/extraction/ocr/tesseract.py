"""Tesseract CLI OCR provider.

The provider consumes rasterized page bytes and parses Tesseract TSV output so
text, confidence, and bounding boxes remain available for provenance.
"""

from __future__ import annotations

import csv
import io
import subprocess
from collections import OrderedDict
from dataclasses import dataclass, field

from engine.extraction.errors import (
    OCRExtractionError,
    OCRProviderUnavailableError,
    OCRTimeoutError,
)
from engine.extraction.ocr.models import OCRTextBlock


@dataclass(slots=True)
class _LineAccumulator:
    words: list[str] = field(default_factory=list)
    confidences: list[float] = field(default_factory=list)
    left: int | None = None
    top: int | None = None
    right: int | None = None
    bottom: int | None = None

    def add_word(
        self,
        *,
        text: str,
        confidence: float | None,
        left: int,
        top: int,
        width: int,
        height: int,
    ) -> None:
        self.words.append(text)
        if confidence is not None:
            self.confidences.append(confidence)
        right = left + width
        bottom = top + height
        self.left = left if self.left is None else min(self.left, left)
        self.top = top if self.top is None else min(self.top, top)
        self.right = right if self.right is None else max(self.right, right)
        self.bottom = bottom if self.bottom is None else max(self.bottom, bottom)

    def confidence(self) -> float | None:
        if not self.confidences:
            return None
        return sum(self.confidences) / len(self.confidences)

    def bounding_box(self) -> tuple[int, int, int, int] | None:
        if None in (self.left, self.top, self.right, self.bottom):
            return None
        return (
            int(self.left),
            int(self.top),
            int(self.right),
            int(self.bottom),
        )


class TesseractOCRProvider:
    """OCR provider backed by the local Tesseract executable."""

    def __init__(
        self,
        *,
        binary: str = "tesseract",
        language: str = "eng",
        page_segmentation_mode: int = 6,
        version_probe_timeout_seconds: float = 5.0,
    ) -> None:
        if not binary.strip():
            raise ValueError("tesseract binary must be non-empty")
        if not language.strip():
            raise ValueError("tesseract language must be non-empty")
        if page_segmentation_mode <= 0:
            raise ValueError("page_segmentation_mode must be greater than zero")
        if version_probe_timeout_seconds <= 0:
            raise ValueError("version probe timeout must be greater than zero")

        self._binary = binary
        self._language = language
        self._psm = page_segmentation_mode
        self._provider_version = self._probe_version(version_probe_timeout_seconds)

    @property
    def provider_id(self) -> str:
        return "tesseract"

    @property
    def provider_version(self) -> str:
        return self._provider_version

    def _probe_version(self, timeout_seconds: float) -> str:
        try:
            result = subprocess.run(
                [self._binary, "--version"],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=timeout_seconds,
                check=False,
            )
        except FileNotFoundError as exc:
            raise OCRProviderUnavailableError(
                "Tesseract executable was not found"
            ) from exc
        except subprocess.TimeoutExpired as exc:
            raise OCRProviderUnavailableError(
                "Tesseract version probe timed out"
            ) from exc
        except OSError as exc:
            raise OCRProviderUnavailableError(
                "Tesseract executable could not be started"
            ) from exc

        if result.returncode != 0:
            raise OCRProviderUnavailableError(
                "Tesseract version probe failed"
            )
        first_line = result.stdout.splitlines()[0].strip() if result.stdout else ""
        return first_line or "tesseract-unknown"

    def extract_page(
        self,
        image_bytes: bytes,
        *,
        page_number: int,
        timeout_seconds: float,
    ) -> tuple[OCRTextBlock, ...]:
        if not image_bytes:
            raise OCRExtractionError("OCR image bytes must not be empty")
        if page_number <= 0:
            raise OCRExtractionError("OCR page_number must be greater than zero")
        if timeout_seconds <= 0:
            raise OCRExtractionError("OCR timeout must be greater than zero")

        command = [
            self._binary,
            "stdin",
            "stdout",
            "-l",
            self._language,
            "--psm",
            str(self._psm),
            "tsv",
        ]
        try:
            result = subprocess.run(
                command,
                input=image_bytes,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout_seconds,
                check=False,
            )
        except FileNotFoundError as exc:
            raise OCRProviderUnavailableError(
                "Tesseract executable was not found"
            ) from exc
        except subprocess.TimeoutExpired as exc:
            raise OCRTimeoutError(
                f"Tesseract OCR timed out after {timeout_seconds} seconds"
            ) from exc
        except OSError as exc:
            raise OCRProviderUnavailableError(
                "Tesseract executable could not be started"
            ) from exc

        if result.returncode != 0:
            stderr = result.stderr.decode("utf-8", errors="replace").strip()
            detail = stderr[:300] if stderr else "unknown Tesseract failure"
            raise OCRExtractionError(f"Tesseract OCR failed: {detail}")

        return self._parse_tsv(result.stdout, page_number=page_number)

    @staticmethod
    def _parse_tsv(tsv_bytes: bytes, *, page_number: int) -> tuple[OCRTextBlock, ...]:
        try:
            payload = tsv_bytes.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise OCRExtractionError("Tesseract TSV output was not UTF-8") from exc

        reader = csv.DictReader(io.StringIO(payload), delimiter="\t")
        required = {
            "level",
            "block_num",
            "par_num",
            "line_num",
            "left",
            "top",
            "width",
            "height",
            "conf",
            "text",
        }
        if reader.fieldnames is None or not required.issubset(reader.fieldnames):
            raise OCRExtractionError("Tesseract TSV output is missing required columns")

        lines: OrderedDict[tuple[int, int, int], _LineAccumulator] = OrderedDict()
        try:
            for row in reader:
                if row.get("level") != "5":
                    continue
                text = (row.get("text") or "").strip()
                if not text:
                    continue
                block_num = int(row["block_num"])
                par_num = int(row["par_num"])
                line_num = int(row["line_num"])
                confidence_raw = float(row["conf"])
                confidence = (
                    max(0.0, min(1.0, confidence_raw / 100.0))
                    if confidence_raw >= 0
                    else None
                )
                key = (block_num, par_num, line_num)
                accumulator = lines.setdefault(key, _LineAccumulator())
                accumulator.add_word(
                    text=text,
                    confidence=confidence,
                    left=int(row["left"]),
                    top=int(row["top"]),
                    width=int(row["width"]),
                    height=int(row["height"]),
                )
        except (KeyError, TypeError, ValueError) as exc:
            raise OCRExtractionError("Tesseract TSV output could not be parsed") from exc

        blocks: list[OCRTextBlock] = []
        for (block_num, par_num, line_num), accumulator in lines.items():
            text = " ".join(accumulator.words).strip()
            if not text:
                continue
            blocks.append(
                OCRTextBlock(
                    locator=(
                        f"page:{page_number}:ocr:block:{block_num}:"
                        f"par:{par_num}:line:{line_num}"
                    ),
                    text=text,
                    page_number=page_number,
                    confidence=accumulator.confidence(),
                    bounding_box=accumulator.bounding_box(),
                )
            )
        return tuple(blocks)
