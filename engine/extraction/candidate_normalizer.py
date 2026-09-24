"""Deterministic MVP normalization from extraction observations to candidates.

The normalizer deliberately handles only explicit, label-led facts that can be
traced to one observed text block. It does not infer missing facts, resolve
conflicts, or produce canonical values. Evidence identity is bound to exact
source bytes, extraction configuration, locator, and raw observed evidence.
"""

from __future__ import annotations

import json
import re
from datetime import UTC, datetime, timedelta, timezone
from hashlib import sha256
from typing import Any

from engine.extraction.errors import CandidateNormalizationError
from engine.extraction.models import NativeDocument
from engine.extraction.ocr.models import OCRDocument
from packages.contracts import (
    CandidateExtractionReport,
    CandidateField,
    EvidenceSpan,
    ExtractionPath,
)

CANDIDATE_NORMALIZER_VERSION = "rule-based-v1"

_MONTH_PATTERN = (
    r"January|February|March|April|May|June|July|August|September|October|"
    r"November|December"
)
_DEADLINE_LABEL_RE = re.compile(
    r"\bsubmission\s+deadline\b\s*[:\-]?\s*(?P<value>.+)$",
    re.IGNORECASE,
)
_DEADLINE_VALUE_RE = re.compile(
    rf"(?P<month>{_MONTH_PATTERN})\s+"
    r"(?P<day>\d{1,2})(?:,)?\s+"
    r"(?P<year>\d{4})"
    r"(?:\s+(?:at\s+)?(?P<hour>\d{1,2})[:.\s](?P<minute>\d{2})"
    r"(?:\s*(?P<timezone>WIB|WITA|WIT|UTC|GMT))?)?",
    re.IGNORECASE,
)
_TEAM_SIZE_LABEL_RE = re.compile(
    r"\bteam\s+size\b\s*[:\-]?\s*(?P<value>.+)$",
    re.IGNORECASE,
)
_TEAM_SIZE_RANGE_RE = re.compile(
    r"(?P<minimum>\d+)\s*(?:to|[-–—])\s*(?P<maximum>\d+)",
    re.IGNORECASE,
)
_TIMEZONE_OFFSETS = {
    "WIB": 7,
    "WITA": 8,
    "WIT": 9,
    "UTC": 0,
    "GMT": 0,
}

ExtractionDocument = NativeDocument | OCRDocument


def _canonical_sha256(material: Any) -> str:
    encoded = json.dumps(
        material,
        sort_keys=True,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    return sha256(encoded).hexdigest()


def _raw_evidence_hash(raw_evidence: str) -> str:
    return sha256(raw_evidence.encode("utf-8")).hexdigest()


def extractor_fingerprint_for_document(document: ExtractionDocument) -> str:
    if isinstance(document, OCRDocument):
        observation_fingerprint = document.extractor_fingerprint or _canonical_sha256(
            {
                "provider_id": document.provider_id,
                "provider_version": document.provider_version,
                "render_dpi": document.render_dpi,
            }
        )
        material = {
            "path": "ocr",
            "observation_fingerprint": observation_fingerprint,
            "candidate_normalizer_version": CANDIDATE_NORMALIZER_VERSION,
        }
        digest = _canonical_sha256(material)
        return (
            f"{document.provider_id}:{document.provider_version}"
            f"|ocr-observation:{observation_fingerprint}"
            f"|candidate-normalizer:{CANDIDATE_NORMALIZER_VERSION}"
            f"|xfp:{digest}"
        )

    material = {
        "path": "native",
        "parser_version": document.parser_version,
        "media_type": document.media_type,
        "candidate_normalizer_version": CANDIDATE_NORMALIZER_VERSION,
    }
    digest = _canonical_sha256(material)
    return (
        f"{document.parser_version}"
        f"|candidate-normalizer:{CANDIDATE_NORMALIZER_VERSION}"
        f"|xfp:{digest}"
    )


def build_evidence_id(
    *,
    source_id: str,
    content_hash: str,
    extraction_path: ExtractionPath,
    field_name: str,
    locator: str,
    extractor_fingerprint: str,
    raw_evidence: str,
) -> str:
    """Build the content/config/raw-observation-bound evidence identity."""

    raw_evidence_hash = _raw_evidence_hash(raw_evidence)
    material = [
        source_id,
        content_hash,
        extraction_path.value,
        field_name,
        locator,
        extractor_fingerprint,
        raw_evidence_hash,
    ]
    return f"ev-{field_name}-{_canonical_sha256(material)}"


def _candidate_confidence(document: ExtractionDocument, block: Any) -> float | None:
    if isinstance(document, OCRDocument):
        return block.confidence
    return None


def _normalize_deadline(value: str) -> str | None:
    match = _DEADLINE_VALUE_RE.search(value)
    if match is None:
        return None

    try:
        parsed_date = datetime.strptime(
            f"{match.group('month')} {match.group('day')} {match.group('year')}",
            "%B %d %Y",
        ).replace(tzinfo=UTC)
    except ValueError:
        return None

    hour = match.group("hour")
    minute = match.group("minute")
    if hour is None or minute is None:
        return parsed_date.date().isoformat()

    timezone_name = (match.group("timezone") or "").upper()
    if not timezone_name:
        return None
    offset_hours = _TIMEZONE_OFFSETS.get(timezone_name)
    if offset_hours is None:
        return None

    try:
        aware = parsed_date.replace(
            hour=int(hour),
            minute=int(minute),
            second=0,
            tzinfo=timezone(timedelta(hours=offset_hours)),
        )
    except ValueError:
        return None
    return aware.isoformat()


def _normalize_team_size(value: str) -> dict[str, int] | None:
    match = _TEAM_SIZE_RANGE_RE.search(value)
    if match is None:
        return None
    minimum = int(match.group("minimum"))
    maximum = int(match.group("maximum"))
    if minimum <= 0 or maximum < minimum:
        return None
    return {"min": minimum, "max": maximum}


class RuleBasedCandidateNormalizer:
    """Small deterministic F-007 MVP normalizer for explicit labeled fields."""

    version = CANDIDATE_NORMALIZER_VERSION

    def normalize(
        self,
        document: ExtractionDocument,
        *,
        extraction_path: ExtractionPath,
    ) -> CandidateExtractionReport:
        if not isinstance(document, (NativeDocument, OCRDocument)):
            raise CandidateNormalizationError(
                "candidate normalizer requires NativeDocument or OCRDocument"
            )

        expected_path = (
            ExtractionPath.OCR
            if isinstance(document, OCRDocument)
            else ExtractionPath.NATIVE
        )
        if extraction_path is not expected_path:
            raise CandidateNormalizationError(
                "candidate normalizer extraction_path does not match document path",
                source_ref=document.source_record.url_or_document_id,
            )

        fields: list[CandidateField] = []
        evidence: list[EvidenceSpan] = []
        seen_fields: set[str] = set()
        extractor_fingerprint = extractor_fingerprint_for_document(document)

        for block in document.blocks:
            if not isinstance(block.locator, str) or not block.locator.strip():
                raise CandidateNormalizationError(
                    "extraction block locator must be a non-empty string",
                    source_ref=document.source_record.url_or_document_id,
                )
            if not isinstance(block.text, str) or not block.text.strip():
                continue

            deadline_match = _DEADLINE_LABEL_RE.search(block.text)
            if deadline_match is not None and "submission_deadline" not in seen_fields:
                raw_value = deadline_match.group("value").strip()
                normalized_value = _normalize_deadline(raw_value)
                if normalized_value is not None:
                    self._append_candidate(
                        document=document,
                        extraction_path=extraction_path,
                        block=block,
                        field_name="submission_deadline",
                        raw_value=raw_value,
                        normalized_value=normalized_value,
                        extractor_fingerprint=extractor_fingerprint,
                        fields=fields,
                        evidence=evidence,
                    )
                    seen_fields.add("submission_deadline")

            team_match = _TEAM_SIZE_LABEL_RE.search(block.text)
            if team_match is not None and "team_size" not in seen_fields:
                raw_value = team_match.group("value").strip()
                normalized_value = _normalize_team_size(raw_value)
                if normalized_value is not None:
                    self._append_candidate(
                        document=document,
                        extraction_path=extraction_path,
                        block=block,
                        field_name="team_size",
                        raw_value=raw_value,
                        normalized_value=normalized_value,
                        extractor_fingerprint=extractor_fingerprint,
                        fields=fields,
                        evidence=evidence,
                    )
                    seen_fields.add("team_size")

        return CandidateExtractionReport(
            source_id=document.source_record.source_id,
            extraction_path=extraction_path,
            fields=fields,
            evidence=evidence,
        )

    @staticmethod
    def _append_candidate(
        *,
        document: ExtractionDocument,
        extraction_path: ExtractionPath,
        block: Any,
        field_name: str,
        raw_value: Any,
        normalized_value: Any,
        extractor_fingerprint: str,
        fields: list[CandidateField],
        evidence: list[EvidenceSpan],
    ) -> None:
        evidence_id = build_evidence_id(
            source_id=document.source_record.source_id,
            content_hash=document.source_record.content_hash,
            extraction_path=extraction_path,
            field_name=field_name,
            locator=block.locator,
            extractor_fingerprint=extractor_fingerprint,
            raw_evidence=block.text,
        )
        evidence.append(
            EvidenceSpan(
                evidence_id=evidence_id,
                source_id=document.source_record.source_id,
                page_or_locator=block.locator,
                raw_text_or_visual_reference=block.text,
                field_name=field_name,
                extraction_path=extraction_path,
                extractor_version=extractor_fingerprint,
            )
        )
        fields.append(
            CandidateField(
                field_name=field_name,
                raw_value=raw_value,
                normalized_value=normalized_value,
                evidence_ids=[evidence_id],
                extraction_path=extraction_path,
                confidence=_candidate_confidence(document, block),
                scope=document.source_record.scope,
            )
        )
