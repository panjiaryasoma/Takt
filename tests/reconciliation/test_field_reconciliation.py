from __future__ import annotations

from datetime import UTC, datetime

import pytest

from engine.reconciliation import ReconciliationInputError, reconcile_field
from packages.contracts import (
    CandidateExtractionReport,
    CandidateField,
    CanonicalFieldState,
    EvidenceSpan,
    ExtractionPath,
    SourceRecord,
    SourceType,
)

NOW = datetime(2026, 9, 24, 8, 0, tzinfo=UTC)


def make_source(
    source_id: str,
    *,
    source_type: SourceType = SourceType.OFFICIAL_RULES,
    authority_basis: str = "official_rules",
    scope=None,
    effective_at: str = "2026-09-01T00:00:00Z",
    supersedes=(),
    update_kind: str | None = None,
    applies_to_fields=(),
    retrieved_at: datetime = NOW,
) -> SourceRecord:
    freshness = {
        "effective_at": effective_at,
        "supersedes_source_ids": list(supersedes),
    }
    if update_kind is not None:
        freshness["update_kind"] = update_kind
    if applies_to_fields:
        freshness["applies_to_fields"] = list(applies_to_fields)
    return SourceRecord(
        source_id=source_id,
        source_type=source_type,
        url_or_document_id=f"https://example.test/{source_id}",
        retrieved_at=retrieved_at,
        content_hash=f"sha256:{source_id}",
        authority_rank={"basis": authority_basis, "tier": 1},
        scope=scope or {"category": "general"},
        freshness_metadata=freshness,
    )


def make_report(
    source_id: str,
    *,
    value,
    normalized,
    path: ExtractionPath = ExtractionPath.NATIVE,
    field_name: str = "submission_deadline",
    scope=None,
    confidence: float | None = 0.9,
    evidence_id: str | None = None,
) -> CandidateExtractionReport:
    evidence_id = evidence_id or f"ev-{source_id}-{path.value}-{field_name}"
    scope = scope or {"category": "general"}
    evidence = EvidenceSpan(
        evidence_id=evidence_id,
        source_id=source_id,
        page_or_locator=f"page:1/{field_name}",
        raw_text_or_visual_reference=str(value),
        field_name=field_name,
        extraction_path=path,
        extractor_version="test-v1",
    )
    field = CandidateField(
        field_name=field_name,
        raw_value=value,
        normalized_value=normalized,
        evidence_ids=[evidence_id],
        extraction_path=path,
        confidence=confidence,
        scope=scope,
    )
    return CandidateExtractionReport(
        source_id=source_id,
        extraction_path=path,
        fields=[field],
        evidence=[evidence],
    )


def test_no_candidate_is_missing() -> None:
    result = reconcile_field("submission_deadline", [], [make_source("src-a")])
    assert result.canonical_field.state is CanonicalFieldState.MISSING
    assert result.resolution_basis == ("no-candidate",)


def test_one_source_one_value_is_single_source() -> None:
    source = make_source("src-a")
    report = make_report(
        "src-a",
        value="Sep 30",
        normalized="2026-09-30T16:59:00Z",
    )
    result = reconcile_field("submission_deadline", [report], [source])
    assert result.canonical_field.state is CanonicalFieldState.SINGLE_SOURCE
    assert result.supporting_source_ids == ("src-a",)


def test_two_independent_sources_same_value_are_verified() -> None:
    sources = [make_source("src-a"), make_source("src-b")]
    reports = [
        make_report("src-a", value="Sep 30", normalized="2026-09-30T16:59:00Z"),
        make_report("src-b", value="September 30", normalized="2026-09-30T16:59:00Z"),
    ]
    result = reconcile_field("submission_deadline", reports, sources)
    assert result.canonical_field.state is CanonicalFieldState.VERIFIED
    assert result.supporting_source_ids == ("src-a", "src-b")


def test_native_and_ocr_same_source_do_not_inflate_verified() -> None:
    source = make_source("src-a")
    reports = [
        make_report(
            "src-a",
            value="Sep 30",
            normalized="2026-09-30T16:59:00Z",
            path=ExtractionPath.NATIVE,
        ),
        make_report(
            "src-a",
            value="September 30",
            normalized="2026-09-30T16:59:00Z",
            path=ExtractionPath.OCR,
        ),
    ]
    result = reconcile_field("submission_deadline", reports, [source])
    assert result.canonical_field.state is CanonicalFieldState.SINGLE_SOURCE
    assert result.supporting_source_ids == ("src-a",)


def test_native_and_ocr_same_source_disagreement_is_conflict() -> None:
    source = make_source("src-a")
    reports = [
        make_report(
            "src-a",
            value="Sep 30",
            normalized="2026-09-30T16:59:00Z",
            path=ExtractionPath.NATIVE,
        ),
        make_report(
            "src-a",
            value="Oct 1",
            normalized="2026-10-01T16:59:00Z",
            path=ExtractionPath.OCR,
        ),
    ]
    result = reconcile_field("submission_deadline", reports, [source])
    assert result.canonical_field.state is CanonicalFieldState.CONFLICT


def test_confidence_does_not_resolve_critical_conflict() -> None:
    sources = [make_source("src-a"), make_source("src-b")]
    reports = [
        make_report(
            "src-a",
            value="Sep 30",
            normalized="2026-09-30T16:59:00Z",
            confidence=0.99,
        ),
        make_report(
            "src-b",
            value="Oct 1",
            normalized="2026-10-01T16:59:00Z",
            confidence=0.60,
        ),
    ]
    result = reconcile_field("submission_deadline", reports, sources)
    assert result.canonical_field.state is CanonicalFieldState.CONFLICT


def test_explicit_authoritative_supersession_resolves_old_value() -> None:
    old = make_source("src-old", effective_at="2026-09-01T00:00:00Z")
    new = make_source(
        "src-new",
        source_type=SourceType.OFFICIAL_ORGANIZER,
        authority_basis="official_organizer",
        effective_at="2026-09-20T00:00:00Z",
        supersedes=("src-old",),
    )
    reports = [
        make_report("src-old", value="Sep 30", normalized="2026-09-30T16:59:00Z"),
        make_report("src-new", value="Oct 2", normalized="2026-10-02T16:59:00Z"),
    ]
    result = reconcile_field("submission_deadline", reports, [old, new])
    assert result.canonical_field.state is CanonicalFieldState.SINGLE_SOURCE
    assert result.canonical_field.normalized_value == "2026-10-02T16:59:00Z"
    assert result.superseded_source_ids == ("src-old",)
    assert len(result.canonical_field.candidates) == 2


def test_field_scoped_update_can_supersede_without_source_pointer() -> None:
    old = make_source("src-old", effective_at="2026-09-01T00:00:00Z")
    new = make_source(
        "src-new",
        source_type=SourceType.OFFICIAL_ORGANIZER,
        authority_basis="official_organizer",
        effective_at="2026-09-20T00:00:00Z",
        update_kind="extension",
        applies_to_fields=("submission_deadline",),
    )
    reports = [
        make_report("src-old", value="Sep 30", normalized="2026-09-30T16:59:00Z"),
        make_report("src-new", value="Oct 2", normalized="2026-10-02T16:59:00Z"),
    ]
    result = reconcile_field("submission_deadline", reports, [old, new])
    assert result.canonical_field.state is CanonicalFieldState.SINGLE_SOURCE
    assert result.canonical_field.normalized_value == "2026-10-02T16:59:00Z"


def test_newer_retrieved_at_alone_never_supersedes() -> None:
    old = make_source(
        "src-old",
        effective_at="2026-09-01T00:00:00Z",
        retrieved_at=datetime(2026, 9, 24, 7, 0, tzinfo=UTC),
    )
    new = make_source(
        "src-new",
        effective_at="2026-09-01T00:00:00Z",
        retrieved_at=datetime(2026, 9, 24, 9, 0, tzinfo=UTC),
    )
    reports = [
        make_report("src-old", value="Sep 30", normalized="2026-09-30T16:59:00Z"),
        make_report("src-new", value="Oct 1", normalized="2026-10-01T16:59:00Z"),
    ]
    result = reconcile_field("submission_deadline", reports, [old, new])
    assert result.canonical_field.state is CanonicalFieldState.CONFLICT


def test_newer_effective_at_without_update_evidence_does_not_supersede() -> None:
    old = make_source("src-old", effective_at="2026-09-01T00:00:00Z")
    new = make_source("src-new", effective_at="2026-09-20T00:00:00Z")
    reports = [
        make_report("src-old", value="Sep 30", normalized="2026-09-30T16:59:00Z"),
        make_report("src-new", value="Oct 1", normalized="2026-10-01T16:59:00Z"),
    ]
    result = reconcile_field("submission_deadline", reports, [old, new])
    assert result.canonical_field.state is CanonicalFieldState.CONFLICT


def test_disjoint_different_values_are_scoped_not_conflict() -> None:
    sources = [make_source("src-a"), make_source("src-b")]
    reports = [
        make_report(
            "src-a",
            field_name="team_size",
            value={"min": 1, "max": 4},
            normalized={"min": 1, "max": 4},
            scope={"category": "general"},
        ),
        make_report(
            "src-b",
            field_name="team_size",
            value={"min": 1, "max": 2},
            normalized={"min": 1, "max": 2},
            scope={"category": "student"},
        ),
    ]
    result = reconcile_field("team_size", reports, sources)
    assert result.canonical_field.state is CanonicalFieldState.SINGLE_SOURCE
    assert "variants" in result.canonical_field.normalized_value
    assert len(result.canonical_field.normalized_value["variants"]) == 2


def test_overlapping_different_values_are_conflict() -> None:
    sources = [make_source("src-a"), make_source("src-b")]
    reports = [
        make_report(
            "src-a",
            field_name="team_size",
            value={"min": 1, "max": 4},
            normalized={"min": 1, "max": 4},
            scope={"category": "all"},
        ),
        make_report(
            "src-b",
            field_name="team_size",
            value={"min": 1, "max": 2},
            normalized={"min": 1, "max": 2},
            scope={"category": "student"},
        ),
    ]
    result = reconcile_field("team_size", reports, sources)
    assert result.canonical_field.state is CanonicalFieldState.CONFLICT


def test_scope_unknown_is_unverified() -> None:
    source = make_source("src-a")
    report = make_report(
        "src-a",
        value="Sep 30",
        normalized="2026-09-30T16:59:00Z",
        scope={},
    )
    # helper's or would replace {}, so mutate after construction to emulate explicit unknown scope
    report.fields[0].scope = {}
    result = reconcile_field("submission_deadline", [report], [source])
    assert result.canonical_field.state is CanonicalFieldState.UNVERIFIED


def test_unusable_normalized_value_is_unverified() -> None:
    source = make_source("src-a")
    report = make_report(
        "src-a",
        value="Sep 30",
        normalized="September 30 someday",
    )
    result = reconcile_field("submission_deadline", [report], [source])
    assert result.canonical_field.state is CanonicalFieldState.UNVERIFIED


def test_same_deadline_in_different_offsets_is_verified() -> None:
    sources = [make_source("src-a"), make_source("src-b")]
    reports = [
        make_report(
            "src-a",
            value="Sep 30 23:59 WIB",
            normalized="2026-09-30T23:59:00+07:00",
        ),
        make_report(
            "src-b",
            value="Sep 30 16:59 UTC",
            normalized="2026-09-30T16:59:00Z",
        ),
    ]
    result = reconcile_field("submission_deadline", reports, sources)
    assert result.canonical_field.state is CanonicalFieldState.VERIFIED
    assert result.canonical_field.normalized_value == "2026-09-30T16:59:00Z"


def test_set_like_list_order_does_not_create_false_conflict() -> None:
    sources = [make_source("src-a"), make_source("src-b")]
    reports = [
        make_report(
            "src-a",
            field_name="deliverables",
            value=["demo_video", "repository"],
            normalized=["demo_video", "repository"],
        ),
        make_report(
            "src-b",
            field_name="deliverables",
            value=["repository", "demo_video"],
            normalized=["repository", "demo_video"],
        ),
    ]
    result = reconcile_field("deliverables", reports, sources)
    assert result.canonical_field.state is CanonicalFieldState.VERIFIED
    assert result.canonical_field.normalized_value == ["demo_video", "repository"]


def test_duplicate_reports_for_same_source_and_path_are_rejected() -> None:
    source = make_source("src-a")
    reports = [
        make_report("src-a", value="Sep 30", normalized="2026-09-30T16:59:00Z"),
        make_report(
            "src-a",
            value="Sep 30",
            normalized="2026-09-30T16:59:00Z",
            evidence_id="ev-second",
        ),
    ]
    with pytest.raises(ReconciliationInputError):
        reconcile_field("submission_deadline", reports, [source])


def test_cross_source_evidence_is_rejected_at_reconciliation_boundary() -> None:
    source = make_source("src-a")
    report = make_report(
        "src-a",
        value="Sep 30",
        normalized="2026-09-30T16:59:00Z",
    )
    report.evidence[0].source_id = "src-other"
    with pytest.raises(ReconciliationInputError):
        reconcile_field("submission_deadline", [report], [source])


def test_all_candidate_evidence_is_preserved_after_supersession() -> None:
    old = make_source("src-old", effective_at="2026-09-01T00:00:00Z")
    new = make_source(
        "src-new",
        source_type=SourceType.OFFICIAL_ORGANIZER,
        authority_basis="official_organizer",
        effective_at="2026-09-20T00:00:00Z",
        supersedes=("src-old",),
    )
    reports = [
        make_report("src-old", value="Sep 30", normalized="2026-09-30T16:59:00Z"),
        make_report("src-new", value="Oct 2", normalized="2026-10-02T16:59:00Z"),
    ]
    result = reconcile_field("submission_deadline", reports, [old, new])
    assert len(result.canonical_field.candidates) == 2
    assert len(result.canonical_field.evidence_ids) == 2


def test_input_order_does_not_change_output() -> None:
    sources = [make_source("src-a"), make_source("src-b")]
    reports = [
        make_report(
            "src-a",
            value="Sep 30 23:59 WIB",
            normalized="2026-09-30T23:59:00+07:00",
        ),
        make_report(
            "src-b",
            value="Sep 30 16:59 UTC",
            normalized="2026-09-30T16:59:00Z",
        ),
    ]
    forward = reconcile_field("submission_deadline", reports, sources)
    reverse = reconcile_field(
        "submission_deadline", list(reversed(reports)), list(reversed(sources))
    )
    assert forward == reverse
