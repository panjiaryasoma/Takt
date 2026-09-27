"""Regression tests for wire-round-tripped previous report versioning."""

from __future__ import annotations

import json
from datetime import UTC, datetime

from engine.reconciliation import (
    CANONICAL_V1,
    assemble_canonical_report,
    material_fingerprint,
)
from engine.reconciliation.models import FieldReconciliationResult
from packages.contracts import (
    CandidateField,
    CanonicalCompetitionReport,
    CanonicalField,
    CanonicalFieldState,
    ExtractionPath,
)


def _field_result(field_name: str, *, deadline: datetime | None = None):
    if field_name != "submission_deadline":
        return FieldReconciliationResult(
            canonical_field=CanonicalField(
                field_name=field_name,
                state=CanonicalFieldState.MISSING,
            ),
            resolution_basis=("test:missing",),
            supporting_source_ids=(),
        )

    evidence_id = "ev-deadline"
    candidate = CandidateField(
        field_name=field_name,
        raw_value="deadline",
        normalized_value=deadline,
        evidence_ids=[evidence_id],
        extraction_path=ExtractionPath.NATIVE,
        confidence=None,
        scope={},
    )
    return FieldReconciliationResult(
        canonical_field=CanonicalField(
            field_name=field_name,
            state=CanonicalFieldState.SINGLE_SOURCE,
            value="deadline",
            normalized_value=deadline,
            candidates=[candidate],
            evidence_ids=[evidence_id],
        ),
        resolution_basis=("test:single",),
        supporting_source_ids=("src-1",),
    )


def _results(deadline: datetime):
    return tuple(
        _field_result(field_name, deadline=deadline)
        for field_name in CANONICAL_V1.core_fields
    )


def test_previous_wire_report_uses_preserved_assembly_fingerprint() -> None:
    deadline = datetime(2026, 9, 30, 23, 45, tzinfo=UTC)
    first = assemble_canonical_report(
        competition_id="cmp-version",
        field_results=_results(deadline),
        snapshot_source_ids=("src-1",),
    )
    raw = json.loads(first.report.model_dump_json())
    round_tripped = CanonicalCompetitionReport.model_validate(raw)

    assert material_fingerprint(round_tripped) != first.material_fingerprint

    second = assemble_canonical_report(
        competition_id="cmp-version",
        field_results=_results(deadline),
        snapshot_source_ids=("src-1",),
        previous_report=round_tripped,
        previous_material_fingerprint=first.material_fingerprint,
    )

    assert second.report_changed is False
    assert second.report.report_version == first.report.report_version


def test_changed_material_increments_previous_wire_report_exactly_once() -> None:
    first_deadline = datetime(2026, 9, 30, 23, 45, tzinfo=UTC)
    second_deadline = datetime(2026, 10, 1, 23, 45, tzinfo=UTC)
    first = assemble_canonical_report(
        competition_id="cmp-version",
        field_results=_results(first_deadline),
        snapshot_source_ids=("src-1",),
    )
    round_tripped = CanonicalCompetitionReport.model_validate(
        json.loads(first.report.model_dump_json())
    )

    changed = assemble_canonical_report(
        competition_id="cmp-version",
        field_results=_results(second_deadline),
        snapshot_source_ids=("src-1",),
        previous_report=round_tripped,
        previous_material_fingerprint=first.material_fingerprint,
    )

    assert changed.report_changed is True
    assert changed.report.report_version == first.report.report_version + 1
