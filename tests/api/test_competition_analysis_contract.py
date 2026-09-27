"""Contract tests for Issue 4A competition-analysis response helpers."""

from __future__ import annotations

from apps.api.contracts import (
    CanonicalReportBundleV1,
    CanonicalReportRefV1,
)
from apps.api.fingerprints import report_wire_fingerprint
from apps.api.services.plan_evaluation import verify_report_bundle
from packages.contracts import (
    CanonicalCompetitionReport,
    CanonicalField,
    CanonicalFieldState,
)
from packages.contracts.source import CORE_CANONICAL_FIELDS


def test_report_ref_semantic_mismatch_is_adapter_validated() -> None:
    report = CanonicalCompetitionReport(
        competition_id="cmp-1",
        report_version=1,
        source_ids=["src-1"],
        canonical_fields={
            name: CanonicalField(
                field_name=name,
                state=CanonicalFieldState.MISSING,
            )
            for name in CORE_CANONICAL_FIELDS
        },
        unresolved_critical_fields=["eligibility", "submission_deadline"],
    )
    initial = CanonicalReportRefV1(
        competition_id="cmp-1",
        report_version=1,
        assembly_material_fingerprint="a" * 64,
        wire_fingerprint="0" * 64,
    )
    ref = initial.model_copy(
        update={"wire_fingerprint": report_wire_fingerprint(report, initial)}
    )
    bundle = CanonicalReportBundleV1(report=report, ref=ref)

    verify_report_bundle(bundle)
