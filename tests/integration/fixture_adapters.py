"""Test-only adapters for preproduction semantic fixtures.

The old POLICY_FIXTURE shape is intentionally not accepted by production code.
These helpers construct the current 13-field CanonicalCompetitionReport wire
model solely for executable integration tests.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from packages.contracts import (
    CandidateField,
    CanonicalCompetitionReport,
    CanonicalField,
    CanonicalFieldState,
    ExtractionPath,
)
from packages.contracts.source import CORE_CANONICAL_FIELDS


def _evidence_ids(field_name: str, payload: Mapping[str, Any]) -> list[str]:
    raw = payload.get("evidence", [])
    if raw:
        return [str(item) for item in raw]
    return [f"fixture:{field_name}:semantic"]


def _usable_field(field_name: str, payload: Mapping[str, Any]) -> CanonicalField:
    state = CanonicalFieldState(payload["state"])
    value = payload.get("value")
    evidence_ids = _evidence_ids(field_name, payload)
    candidate = CandidateField(
        field_name=field_name,
        raw_value=value,
        normalized_value=value,
        evidence_ids=evidence_ids,
        extraction_path=ExtractionPath.NATIVE,
        confidence=None,
        scope={"category": "all"},
    )
    return CanonicalField(
        field_name=field_name,
        state=state,
        value=value,
        normalized_value=value,
        candidates=[candidate],
        evidence_ids=evidence_ids,
    )


def canonical_report_from_preproduction_fixture(
    fixture: Mapping[str, Any],
) -> CanonicalCompetitionReport:
    semantic_fields = fixture["canonical_report"]
    canonical_fields: dict[str, CanonicalField] = {}

    for field_name in sorted(CORE_CANONICAL_FIELDS):
        payload = semantic_fields.get(field_name)
        if payload is None:
            canonical_fields[field_name] = CanonicalField(
                field_name=field_name,
                state=CanonicalFieldState.MISSING,
            )
            continue

        state = CanonicalFieldState(payload["state"])
        if state is CanonicalFieldState.MISSING:
            canonical_fields[field_name] = CanonicalField(
                field_name=field_name,
                state=state,
            )
            continue
        canonical_fields[field_name] = _usable_field(field_name, payload)

    source_ids = sorted(
        {
            evidence.split(":", 1)[0]
            for payload in semantic_fields.values()
            if isinstance(payload, Mapping)
            for evidence in payload.get("evidence", [])
        }
    )
    if not source_ids:
        source_ids = ["preproduction-fixture"]

    return CanonicalCompetitionReport(
        competition_id="INTEGRATION-001",
        report_version=1,
        source_ids=source_ids,
        canonical_fields=canonical_fields,
        unresolved_critical_fields=list(
            semantic_fields.get("unresolved_critical_fields", [])
        ),
    )
