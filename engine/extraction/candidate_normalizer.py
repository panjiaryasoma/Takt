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

CANDIDATE_NORMALIZER_VERSION = "rule-based-v5"

_MONTH_PATTERN = (
    r"January|February|March|April|May|June|July|August|September|October|"
    r"November|December|Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec"
)
_FACT_LABEL_RE = re.compile(
    r"\b(?P<label>submission\s+deadline(?=\s*[:\-])|"
    r"submission\s+period(?=\s*[:\-])|"
    r"registration\s+deadline(?=\s*[:\-])|"
    r"deadline(?=\s*[:\-])|team\s+size(?=\s*[:\-]))"
    r"\b\s*[:\-]\s*",
    re.IGNORECASE,
)
_DEADLINE_VALUE_RE = re.compile(
    rf"(?P<month>{_MONTH_PATTERN})\s+"
    r"(?P<day>\d{1,2})(?:,)?\s+"
    r"(?P<year>\d{4})"
    r"(?:\s+(?:(?:at\s+)|(?:@\s*))?(?P<hour>\d{1,2})"
    r"[:.](?P<minute>\d{2})\s*(?P<meridiem>am|pm)?\s*"
    r"(?P<timezone>WIB|WITA|WIT|UTC|GMT|PDT|PST|MDT|MST|CDT|CST|EDT|EST)"
    r"(?!\w|\s*[+-]))?",
    re.IGNORECASE,
)
_OFFICIAL_RULES_NAME_RE = re.compile(
    r"^\s*(?P<name>.+?)\s*"
    r"(?:\(\s*the\s+[“\"']?Hackathon[”\"']?\s*\)\s*)?"
    r"Official\s+Rules\s*$",
    re.IGNORECASE,
)
_SPONSOR_RE = re.compile(r"^\s*Sponsor\s*:\s*(?P<value>.+?)\s*$", re.IGNORECASE)
_TEAM_SIZE_RANGE_RE = re.compile(
    r"(?P<minimum>\d+)\s*(?:to|[-–—])\s*(?P<maximum>\d+)",
    re.IGNORECASE,
)
_ELIGIBILITY_OPEN_RE = re.compile(
    r"The\s+Hackathon\s+IS\s+open\s+to\s*:",
    re.IGNORECASE,
)
_AGE_OF_MAJORITY_RE = re.compile(r"age\s+of\s+majority", re.IGNORECASE)
_SUBMISSION_REQUIREMENTS_RE = re.compile(
    r"Submission\s+Requirements",
    re.IGNORECASE,
)
_PROJECT_REQUIREMENTS_RE = re.compile(
    r"Project\s+Requirements",
    re.IGNORECASE,
)
_ELIGIBILITY_SECTION_START_RE = re.compile(
    r"^(?:\d+\.\s*)?Eligibility\b",
    re.IGNORECASE,
)
_ELIGIBILITY_SECTION_END_RE = re.compile(
    r"^(?:\d+\.\s*)?How\s+To\s+Enter\b",
    re.IGNORECASE,
)
_PROJECT_SECTION_START_RE = re.compile(
    r"^Project\s+Requirements\b",
    re.IGNORECASE,
)
_PROJECT_SECTION_END_RE = re.compile(
    r"^Submission\s+Requirements\b",
    re.IGNORECASE,
)
_SUBMISSION_SECTION_START_RE = re.compile(
    r"^Submission\s+Requirements\b",
    re.IGNORECASE,
)
_SUBMISSION_SECTION_END_RE = re.compile(
    r"^(?:Multiple\s+Submissions|Submission\s+ownership|Submission\s+Ownership)\b",
    re.IGNORECASE,
)

_TIMEZONE_OFFSETS = {
    "WIB": 7,
    "WITA": 8,
    "WIT": 9,
    "UTC": 0,
    "GMT": 0,
    "PDT": -7,
    "PST": -8,
    "MDT": -6,
    "MST": -7,
    "CDT": -5,
    "CST": -6,
    "EDT": -4,
    "EST": -5,
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


class _AmbiguousLabeledValue(ValueError):
    """One explicit label contains alternatives the V1 candidate shape cannot represent."""


_ALTERNATIVE_VALUE_RE = re.compile(r"\s+(?:or)\s+|\s*/\s*", re.IGNORECASE)


def _deadline_from_match(match: re.Match[str]) -> str | None:
    date_text = (
        f"{match.group('month')} {match.group('day')} {match.group('year')}"
    )
    parsed_date = None
    for date_format in ("%B %d %Y", "%b %d %Y"):
        try:
            parsed_date = datetime.strptime(date_text, date_format).replace(tzinfo=UTC)
            break
        except ValueError:
            continue
    if parsed_date is None:
        return None

    hour = match.group("hour")
    minute = match.group("minute")
    if hour is None or minute is None:
        return parsed_date.date().isoformat()

    timezone_name = (match.group("timezone") or "").upper()
    offset_hours = _TIMEZONE_OFFSETS.get(timezone_name)
    if offset_hours is None:
        return None

    hour_value = int(hour)
    meridiem = (match.group("meridiem") or "").lower()
    if meridiem:
        if not 1 <= hour_value <= 12:
            return None
        if meridiem == "am":
            hour_value = 0 if hour_value == 12 else hour_value
        else:
            hour_value = 12 if hour_value == 12 else hour_value + 12

    try:
        aware = parsed_date.replace(
            hour=hour_value,
            minute=int(minute),
            second=0,
            tzinfo=timezone(timedelta(hours=offset_hours)),
        )
    except ValueError:
        return None
    return aware.isoformat()


def _deadline_key(value: str) -> tuple[str, object]:
    if "T" not in value:
        return ("date", value)
    return ("instant", datetime.fromisoformat(value).astimezone(UTC))


def _normalize_deadline(value: str) -> str | None:
    cleaned = value.strip()
    alternatives = tuple(
        item.strip()
        for item in _ALTERNATIVE_VALUE_RE.split(cleaned)
        if item.strip()
    )
    if not alternatives:
        return None

    normalized: list[str | None] = []
    first_matches: list[re.Match[str] | None] = []
    for alternative in alternatives:
        match = _DEADLINE_VALUE_RE.match(alternative)
        first_matches.append(match)
        normalized.append(_deadline_from_match(match) if match is not None else None)

    supported = [item for item in normalized if item is not None]
    if not supported:
        return None
    if len(supported) != len(normalized):
        raise _AmbiguousLabeledValue(
            "deadline alternatives mix supported and unsupported values"
        )

    # Do not let a valid prefix hide another direct supported deadline later in
    # the same labeled value. The V1 candidate shape cannot represent both.
    observed = list(supported)
    for alternative, first in zip(alternatives, first_matches, strict=True):
        if first is None:
            continue
        tail = alternative[first.end():]
        # An explicit but unsupported time suffix must not downgrade to a
        # date-only fact merely because the time grammar failed.
        if first.group("hour") is None and re.match(
            r"^\s*(?:at\b|@)",
            tail,
            re.IGNORECASE,
        ):
            raise _AmbiguousLabeledValue(
                "deadline contains an unsupported explicit time"
            )
        for extra in _DEADLINE_VALUE_RE.finditer(tail):
            parsed = _deadline_from_match(extra)
            if parsed is None:
                raise _AmbiguousLabeledValue(
                    "deadline alternatives mix supported and unsupported values"
                )
            observed.append(parsed)

    if len({_deadline_key(item) for item in observed}) != 1:
        raise _AmbiguousLabeledValue("deadline alternatives disagree")
    return supported[0]


def _competition_name_from_text(value: str) -> str | None:
    match = _OFFICIAL_RULES_NAME_RE.match(value)
    if match is None:
        return None
    cleaned = " ".join(match.group("name").split()).strip(" :-")
    return cleaned or None


def _organizer_from_sponsor_text(value: str) -> str | None:
    match = _SPONSOR_RE.match(value)
    if match is None:
        return None

    cleaned = " ".join(match.group("value").split())
    parts = [part.strip() for part in cleaned.split(",") if part.strip()]
    if not parts:
        return None
    if len(parts) >= 2 and parts[1].lower().rstrip(".") in {
        "inc",
        "llc",
        "l.l.c",
        "ltd",
        "corp",
        "corporation",
    }:
        return f"{parts[0]}, {parts[1]}"
    return parts[0]


def _normalize_generic_deadline(value: str) -> str | None:
    """Parse only the timestamp immediately following a generic Deadline label.

    Generic platform headers often live in a large container whose remaining
    text includes unrelated dates. Those later dates must not be interpreted
    as alternatives to the header deadline.
    """

    match = _DEADLINE_VALUE_RE.match(value.strip())
    if match is None:
        return None
    return _deadline_from_match(match)


_PACIFIC_RANGE_END_RE = re.compile(
    rf"(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),\s+"
    rf"(?P<month>{_MONTH_PATTERN})\s+(?P<day>\d{{1,2}}),\s+(?P<year>\d{{4}})"
    r"\s*\(\s*(?P<hour>\d{1,2})[:.](?P<minute>\d{2})\s*"
    r"(?P<meridiem>am|pm)\s+Pacific\s+Time\s*\)",
    re.IGNORECASE,
)


def _normalize_submission_period(value: str) -> str | None:
    """Return the end instant from a Devpost-style submission period range."""

    matches = list(_PACIFIC_RANGE_END_RE.finditer(value))
    if not matches:
        return None
    end = matches[-1]
    month = end.group("month")
    day = end.group("day")
    year = end.group("year")
    hour = int(end.group("hour"))
    minute = int(end.group("minute"))
    meridiem = end.group("meridiem").lower()
    if meridiem == "am":
        hour = 0 if hour == 12 else hour
    else:
        hour = 12 if hour == 12 else hour + 12

    date_text = f"{month} {day} {year}"
    parsed_date = None
    for date_format in ("%B %d %Y", "%b %d %Y"):
        try:
            parsed_date = datetime.strptime(date_text, date_format).replace(
                tzinfo=timezone(timedelta(hours=-7))
            )
            break
        except ValueError:
            continue
    if parsed_date is None:
        return None

    # Devpost's "Pacific Time" is PDT for late October 2026.
    aware = parsed_date.replace(
        hour=hour,
        minute=minute,
        second=0,
    )
    return aware.isoformat()


def _section_blocks(
    blocks: tuple[Any, ...],
    *,
    start: re.Pattern[str],
    end: re.Pattern[str],
) -> tuple[Any, ...]:
    active = False
    collected: list[Any] = []
    for block in blocks:
        text = block.text.strip()
        if not active:
            if start.search(text) is None:
                continue
            active = True
            collected.append(block)
            continue
        if end.search(text) is not None:
            break
        collected.append(block)
    return tuple(collected)


def _joined_block_text(blocks: tuple[Any, ...]) -> str:
    return "\n".join(block.text.strip() for block in blocks if block.text.strip())


def _eligibility_from_text(value: str) -> dict[str, object] | None:
    if _ELIGIBILITY_OPEN_RE.search(value) is None:
        return None
    if _AGE_OF_MAJORITY_RE.search(value) is None:
        return None

    # V1 eligibility can only represent a numeric minimum age, not a
    # jurisdiction-dependent "age of majority" rule. Use 21 as a conservative
    # projection so the system avoids false-positive eligibility for minors.
    # Region exclusions remain visible in raw evidence but are not representable
    # by the frozen positive-list contract.
    return {
        "minimum_age": 21,
        "requires_student": False,
        "allowed_regions": [],
    }


def _deliverables_from_text(value: str) -> list[str] | None:
    if _SUBMISSION_REQUIREMENTS_RE.search(value) is None:
        return None

    deliverables: list[str] = []
    probes = (
        ("working demo", r"URL\s+to\s+a\s+working\s+demo|hosted\s+application|test\s+build"),
        ("text description", r"text\s+description"),
        ("public code repository", r"public\s+code\s+repository"),
        ("README with setup instructions", r"README\s+with\s+setup\s+instructions"),
        ("demonstration video", r"demonstration\s+video"),
        ("track selection", r"Identify\s+which\s+track"),
        ("tool feedback", r"Provide\s+feedback\s+on\s+Nebius"),
    )
    for label, pattern in probes:
        if re.search(pattern, value, re.IGNORECASE):
            deliverables.append(label)
    return deliverables or None


def _required_technologies_from_text(value: str) -> list[str] | None:
    if _PROJECT_REQUIREMENTS_RE.search(value) is None:
        return None
    if "Nebius" not in value or "NVIDIA" not in value:
        return None

    technologies: list[str] = []
    if re.search(r"Nebius\s+Token\s+Factory", value, re.IGNORECASE):
        technologies.append("Nebius Token Factory or Nebius AI Cloud")
    if re.search(r"NVIDIA\s+open\s+source\s+model", value, re.IGNORECASE):
        technologies.append("at least one NVIDIA open source model")
    return technologies or None


def _team_size_from_text(value: str) -> dict[str, int] | None:
    match = _TEAM_SIZE_RANGE_RE.match(value)
    if match is None:
        return None
    minimum = int(match.group("minimum"))
    maximum = int(match.group("maximum"))
    if minimum <= 0 or maximum < minimum:
        return None
    return {"min": minimum, "max": maximum}


def _normalize_team_size(value: str) -> dict[str, int] | None:
    alternatives = tuple(
        item.strip()
        for item in _ALTERNATIVE_VALUE_RE.split(value.strip())
        if item.strip()
    )
    if not alternatives:
        return None

    normalized = [_team_size_from_text(item) for item in alternatives]
    supported = [item for item in normalized if item is not None]
    if not supported:
        return None
    if len(supported) != len(normalized):
        raise _AmbiguousLabeledValue(
            "team-size alternatives mix supported and unsupported values"
        )

    observed = list(supported)
    for alternative in alternatives:
        first = _TEAM_SIZE_RANGE_RE.match(alternative)
        if first is None:
            continue
        for extra in _TEAM_SIZE_RANGE_RE.finditer(alternative, first.end()):
            minimum = int(extra.group("minimum"))
            maximum = int(extra.group("maximum"))
            if minimum <= 0 or maximum < minimum:
                raise _AmbiguousLabeledValue(
                    "team-size alternatives mix supported and unsupported values"
                )
            observed.append({"min": minimum, "max": maximum})

    keys = {(item["min"], item["max"]) for item in observed}
    if len(keys) != 1:
        raise _AmbiguousLabeledValue("team-size alternatives disagree")
    return supported[0]


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
        parsed_by_field: dict[str, bool] = {}
        extractor_fingerprint = extractor_fingerprint_for_document(document)

        for block in document.blocks:
            if not isinstance(block.locator, str) or not block.locator.strip():
                raise CandidateNormalizationError(
                    "extraction block locator must be a non-empty string",
                    source_ref=document.source_record.url_or_document_id,
                )
            if not isinstance(block.text, str) or not block.text.strip():
                continue

            competition_name = _competition_name_from_text(block.text)
            if competition_name is not None:
                self._append_candidate(
                    document=document,
                    extraction_path=extraction_path,
                    block=block,
                    field_name="competition_name",
                    raw_value=competition_name,
                    normalized_value=competition_name,
                    extractor_fingerprint=extractor_fingerprint,
                    fields=fields,
                    evidence=evidence,
                )

            organizer = _organizer_from_sponsor_text(block.text)
            if organizer is not None:
                self._append_candidate(
                    document=document,
                    extraction_path=extraction_path,
                    block=block,
                    field_name="organizer",
                    raw_value=organizer,
                    normalized_value=organizer,
                    extractor_fingerprint=extractor_fingerprint,
                    fields=fields,
                    evidence=evidence,
                )

            matches = list(_FACT_LABEL_RE.finditer(block.text))
            for index, match in enumerate(matches):
                end = matches[index + 1].start() if index + 1 < len(matches) else len(block.text)
                raw_value = block.text[match.end():end].strip()
                try:
                    label = " ".join(match.group("label").lower().split())
                    if label == "submission deadline":
                        field_name = "submission_deadline"
                        normalized_value = _normalize_deadline(raw_value)
                    elif label == "submission period":
                        field_name = "submission_deadline"
                        normalized_value = _normalize_submission_period(raw_value)
                    elif label == "deadline":
                        field_name = "submission_deadline"
                        normalized_value = _normalize_generic_deadline(raw_value)
                        if normalized_value is None:
                            # Generic page chrome may contain unrelated Deadline:
                            # labels. Ignore unsupported generic labels instead of
                            # poisoning an explicit/structured submission deadline.
                            continue
                    elif label == "registration deadline":
                        field_name = "registration_deadline"
                        normalized_value = _normalize_deadline(raw_value)
                    else:
                        field_name = "team_size"
                        normalized_value = _normalize_team_size(raw_value)
                except _AmbiguousLabeledValue as exc:
                    raise CandidateNormalizationError(
                        "source contains conflicting labeled facts",
                        source_ref=document.source_record.url_or_document_id,
                    ) from exc
                parsed = normalized_value is not None
                if field_name in parsed_by_field and parsed_by_field[field_name] != parsed:
                    raise CandidateNormalizationError(
                        "source contains conflicting supported and unsupported labeled facts",
                        source_ref=document.source_record.url_or_document_id,
                    )
                parsed_by_field[field_name] = parsed
                if normalized_value is not None:
                    self._append_candidate(
                        document=document,
                        extraction_path=extraction_path,
                        block=block,
                        field_name=field_name,
                        raw_value=raw_value,
                        normalized_value=normalized_value,
                        extractor_fingerprint=extractor_fingerprint,
                        fields=fields,
                        evidence=evidence,
                    )

        eligibility_blocks = _section_blocks(
            document.blocks,
            start=_ELIGIBILITY_SECTION_START_RE,
            end=_ELIGIBILITY_SECTION_END_RE,
        )
        eligibility_text = _joined_block_text(eligibility_blocks)
        eligibility = _eligibility_from_text(eligibility_text)
        if eligibility is not None:
            self._append_candidate_from_blocks(
                document=document,
                extraction_path=extraction_path,
                blocks=eligibility_blocks,
                field_name="eligibility",
                raw_value=eligibility_text,
                normalized_value=eligibility,
                extractor_fingerprint=extractor_fingerprint,
                fields=fields,
                evidence=evidence,
            )

        project_blocks = _section_blocks(
            document.blocks,
            start=_PROJECT_SECTION_START_RE,
            end=_PROJECT_SECTION_END_RE,
        )
        project_text = _joined_block_text(project_blocks)
        required_technologies = _required_technologies_from_text(project_text)
        if required_technologies is not None:
            self._append_candidate_from_blocks(
                document=document,
                extraction_path=extraction_path,
                blocks=project_blocks,
                field_name="required_technologies",
                raw_value=project_text,
                normalized_value=required_technologies,
                extractor_fingerprint=extractor_fingerprint,
                fields=fields,
                evidence=evidence,
            )

        submission_blocks = _section_blocks(
            document.blocks,
            start=_SUBMISSION_SECTION_START_RE,
            end=_SUBMISSION_SECTION_END_RE,
        )
        submission_text = _joined_block_text(submission_blocks)
        deliverables = _deliverables_from_text(submission_text)
        if deliverables is not None:
            self._append_candidate_from_blocks(
                document=document,
                extraction_path=extraction_path,
                blocks=submission_blocks,
                field_name="deliverables",
                raw_value=submission_text,
                normalized_value=deliverables,
                extractor_fingerprint=extractor_fingerprint,
                fields=fields,
                evidence=evidence,
            )

        return CandidateExtractionReport(
            source_id=document.source_record.source_id,
            extraction_path=extraction_path,
            fields=fields,
            evidence=evidence,
        )

    @staticmethod
    def _append_candidate_from_blocks(
        *,
        document: ExtractionDocument,
        extraction_path: ExtractionPath,
        blocks: tuple[Any, ...],
        field_name: str,
        raw_value: Any,
        normalized_value: Any,
        extractor_fingerprint: str,
        fields: list[CandidateField],
        evidence: list[EvidenceSpan],
    ) -> None:
        if not blocks:
            return

        for previous in fields:
            if previous.field_name != field_name:
                continue
            if previous.normalized_value == normalized_value:
                return
            raise CandidateNormalizationError(
                "source contains conflicting labeled facts",
                source_ref=document.source_record.url_or_document_id,
            )

        evidence_ids: list[str] = []
        confidences: list[float] = []
        for block in blocks:
            evidence_id = build_evidence_id(
                source_id=document.source_record.source_id,
                content_hash=document.source_record.content_hash,
                extraction_path=extraction_path,
                field_name=field_name,
                locator=block.locator,
                extractor_fingerprint=extractor_fingerprint,
                raw_evidence=block.text,
            )
            evidence_ids.append(evidence_id)
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
            confidence = _candidate_confidence(document, block)
            if confidence is not None:
                confidences.append(confidence)

        fields.append(
            CandidateField(
                field_name=field_name,
                raw_value=raw_value,
                normalized_value=normalized_value,
                evidence_ids=evidence_ids,
                extraction_path=extraction_path,
                confidence=min(confidences) if confidences else None,
                scope=document.source_record.scope,
            )
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
        for previous in fields:
            if previous.field_name != field_name:
                continue
            agrees = previous.normalized_value == normalized_value
            if field_name == "submission_deadline":
                agrees = datetime.fromisoformat(previous.normalized_value) == datetime.fromisoformat(
                    normalized_value
                )
            if agrees:
                return
            # The wire contract permits one field per source/path. Ambiguity
            # cannot be represented by silently selecting either observation.
            raise CandidateNormalizationError(
                "source contains conflicting labeled facts",
                source_ref=document.source_record.url_or_document_id,
            )

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
