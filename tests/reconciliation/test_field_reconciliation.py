from __future__ import annotations

from datetime import UTC, datetime

import pytest

from engine.reconciliation import (
    ReconciliationInputError,
    collect_candidate_observations,
    reconcile_field,
)
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
    authority_basis: str | None = None,
    authority_rank=None,
    scope=None,
    effective_at: str | None = "2026-09-01T00:00:00Z",
    supersedes=(),
    update_kind: str | None = None,
    applies_to_fields=(),
    freshness_metadata=None,
    retrieved_at: datetime = NOW,
) -> SourceRecord:
    if freshness_metadata is None:
        freshness = {
            "effective_at": effective_at,
            "supersedes_source_ids": list(supersedes),
        }
        if update_kind is not None:
            freshness["update_kind"] = update_kind
        if applies_to_fields:
            freshness["applies_to_fields"] = list(applies_to_fields)
    else:
        freshness = freshness_metadata

    if authority_rank is None:
        basis = authority_basis or source_type.value
        authority_rank = {"basis": basis, "tier": 1}

    return SourceRecord(
        source_id=source_id,
        source_type=source_type,
        url_or_document_id=f"https://example.test/{source_id}",
        retrieved_at=retrieved_at,
        content_hash=f"sha256:{source_id}",
        authority_rank=authority_rank,
        scope={"category": "all"} if scope is None else scope,
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
    extractor_version: str = "test-v1",
) -> CandidateExtractionReport:
    evidence_id = evidence_id or f"ev-{source_id}-{path.value}-{field_name}"
    effective_scope = {"category": "all"} if scope is None else scope
    evidence = EvidenceSpan(
        evidence_id=evidence_id,
        source_id=source_id,
        page_or_locator=f"page:1/{field_name}",
        raw_text_or_visual_reference=str(value),
        field_name=field_name,
        extraction_path=path,
        extractor_version=extractor_version,
    )
    field = CandidateField(
        field_name=field_name,
        raw_value=value,
        normalized_value=normalized,
        evidence_ids=[evidence_id],
        extraction_path=path,
        confidence=confidence,
        scope=effective_scope,
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


def test_same_value_disjoint_scopes_do_not_inflate_verified() -> None:
    sources = [
        make_source("src-a", scope={"category": "student"}),
        make_source("src-b", scope={"category": "professional"}),
    ]
    reports = [
        make_report(
            "src-a",
            field_name="team_size",
            value=2,
            normalized=2,
            scope={"category": "student"},
        ),
        make_report(
            "src-b",
            field_name="team_size",
            value=2,
            normalized=2,
            scope={"category": "professional"},
        ),
    ]
    result = reconcile_field("team_size", reports, sources)

    assert result.canonical_field.state is CanonicalFieldState.SINGLE_SOURCE
    assert len(result.canonical_field.normalized_value["variants"]) == 2
    assert result.supporting_source_ids == ("src-a", "src-b")


def test_same_value_overlapping_scopes_can_corroborate() -> None:
    sources = [
        make_source("src-a", scope={"category": "all"}),
        make_source("src-b", scope={"category": "student"}),
    ]
    reports = [
        make_report(
            "src-a",
            field_name="team_size",
            value=2,
            normalized=2,
            scope={"category": "all"},
        ),
        make_report(
            "src-b",
            field_name="team_size",
            value=2,
            normalized=2,
            scope={"category": "student"},
        ),
    ]
    result = reconcile_field("team_size", reports, sources)
    assert result.canonical_field.state is CanonicalFieldState.VERIFIED


def test_source_scope_caps_candidate_scope() -> None:
    source = make_source("src-a", scope={"category": "student"})
    report = make_report(
        "src-a",
        field_name="team_size",
        value=2,
        normalized=2,
        scope={"category": "all"},
    )

    observation = collect_candidate_observations([report], [source])[0]
    assert observation.effective_scope.as_mapping() == {
        "audience": None,
        "category": "student",
        "region": None,
    }


def test_candidate_scope_disjoint_from_source_scope_is_rejected() -> None:
    source = make_source("src-a", scope={"category": "student"})
    report = make_report(
        "src-a",
        field_name="team_size",
        value=2,
        normalized=2,
        scope={"category": "professional"},
    )

    with pytest.raises(ReconciliationInputError):
        reconcile_field("team_size", [report], [source])


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
        effective_at="2026-09-20T00:00:00Z",
        supersedes=("src-old",),
        update_kind="extension",
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


def test_field_scoped_organizer_update_can_supersede_same_scope() -> None:
    old = make_source(
        "src-old",
        scope={"category": "student"},
        effective_at="2026-09-01T00:00:00Z",
    )
    new = make_source(
        "src-new",
        source_type=SourceType.OFFICIAL_ORGANIZER,
        scope={"category": "student"},
        effective_at="2026-09-20T00:00:00Z",
        update_kind="extension",
        applies_to_fields=("submission_deadline",),
    )
    reports = [
        make_report(
            "src-old",
            value="Sep 30",
            normalized="2026-09-30T16:59:00Z",
            scope={"category": "student"},
        ),
        make_report(
            "src-new",
            value="Oct 2",
            normalized="2026-10-02T16:59:00Z",
            scope={"category": "student"},
        ),
    ]
    result = reconcile_field("submission_deadline", reports, [old, new])
    assert result.canonical_field.state is CanonicalFieldState.SINGLE_SOURCE
    assert result.canonical_field.normalized_value == "2026-10-02T16:59:00Z"


def test_narrow_update_does_not_erase_broader_rule() -> None:
    old = make_source(
        "src-old",
        scope={"category": "all"},
        effective_at="2026-09-01T00:00:00Z",
    )
    new = make_source(
        "src-new",
        source_type=SourceType.OFFICIAL_ORGANIZER,
        scope={"category": "student"},
        effective_at="2026-09-20T00:00:00Z",
        update_kind="extension",
        applies_to_fields=("submission_deadline",),
    )
    reports = [
        make_report(
            "src-old",
            value="Sep 30",
            normalized="2026-09-30T16:59:00Z",
            scope={"category": "all"},
        ),
        make_report(
            "src-new",
            value="Oct 2",
            normalized="2026-10-02T16:59:00Z",
            scope={"category": "all"},
        ),
    ]
    result = reconcile_field("submission_deadline", reports, [old, new])
    assert result.canonical_field.state is CanonicalFieldState.CONFLICT


def test_newer_faq_does_not_silently_override_official_rules() -> None:
    old = make_source(
        "src-rules",
        source_type=SourceType.OFFICIAL_RULES,
        effective_at="2026-09-01T00:00:00Z",
    )
    faq = make_source(
        "src-faq",
        source_type=SourceType.OFFICIAL_FAQ,
        effective_at="2026-09-20T00:00:00Z",
        update_kind="extension",
        applies_to_fields=("submission_deadline",),
    )
    reports = [
        make_report("src-rules", value="Sep 30", normalized="2026-09-30T16:59:00Z"),
        make_report("src-faq", value="Oct 2", normalized="2026-10-02T16:59:00Z"),
    ]
    result = reconcile_field("submission_deadline", reports, [old, faq])
    assert result.canonical_field.state is CanonicalFieldState.CONFLICT


def test_faq_can_corroborate_rules_when_value_agrees() -> None:
    rules = make_source("src-rules", source_type=SourceType.OFFICIAL_RULES)
    faq = make_source("src-faq", source_type=SourceType.OFFICIAL_FAQ)
    reports = [
        make_report("src-rules", value="Sep 30", normalized="2026-09-30T16:59:00Z"),
        make_report("src-faq", value="Sep 30", normalized="2026-09-30T16:59:00Z"),
    ]
    result = reconcile_field("submission_deadline", reports, [rules, faq])
    assert result.canonical_field.state is CanonicalFieldState.VERIFIED


def test_secondary_source_cannot_supersede_official_source() -> None:
    official = make_source(
        "src-official",
        source_type=SourceType.OFFICIAL_RULES,
        effective_at="2026-09-01T00:00:00Z",
    )
    secondary = make_source(
        "src-secondary",
        source_type=SourceType.SECONDARY,
        effective_at="2026-09-20T00:00:00Z",
        update_kind="replacement",
        supersedes=("src-official",),
    )
    reports = [
        make_report(
            "src-official",
            value="Sep 30",
            normalized="2026-09-30T16:59:00Z",
        ),
        make_report(
            "src-secondary",
            value="Oct 2",
            normalized="2026-10-02T16:59:00Z",
        ),
    ]
    result = reconcile_field("submission_deadline", reports, [official, secondary])
    assert result.canonical_field.state is CanonicalFieldState.CONFLICT


def test_older_effective_at_cannot_supersede_even_with_explicit_pointer() -> None:
    current = make_source(
        "src-current",
        effective_at="2026-09-20T00:00:00Z",
    )
    older_replacement = make_source(
        "src-older-replacement",
        source_type=SourceType.OFFICIAL_ORGANIZER,
        effective_at="2026-09-01T00:00:00Z",
        update_kind="replacement",
        supersedes=("src-current",),
    )
    reports = [
        make_report(
            "src-current",
            value="Oct 2",
            normalized="2026-10-02T16:59:00Z",
        ),
        make_report(
            "src-older-replacement",
            value="Sep 30",
            normalized="2026-09-30T16:59:00Z",
        ),
    ]
    result = reconcile_field(
        "submission_deadline",
        reports,
        [current, older_replacement],
    )
    assert result.canonical_field.state is CanonicalFieldState.CONFLICT


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
    sources = [
        make_source("src-a", scope={"category": "general"}),
        make_source("src-b", scope={"category": "student"}),
    ]
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
    sources = [
        make_source("src-a", scope={"category": "all"}),
        make_source("src-b", scope={"category": "student"}),
    ]
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


def test_unknown_scope_is_unverified() -> None:
    source = make_source("src-a", scope={})
    report = make_report(
        "src-a",
        value="Sep 30",
        normalized="2026-09-30T16:59:00Z",
        scope={},
    )
    result = reconcile_field("submission_deadline", [report], [source])
    assert result.canonical_field.state is CanonicalFieldState.UNVERIFIED


def test_unknown_but_well_formed_freshness_is_unverified() -> None:
    source = make_source("src-a", freshness_metadata={})
    report = make_report(
        "src-a",
        value="Sep 30",
        normalized="2026-09-30T16:59:00Z",
    )
    result = reconcile_field("submission_deadline", [report], [source])
    assert result.canonical_field.state is CanonicalFieldState.UNVERIFIED
    assert result.resolution_basis == ("freshness-unknown",)


def test_malformed_authority_metadata_is_rejected() -> None:
    source = make_source("src-a", authority_rank="high")
    report = make_report(
        "src-a",
        value="Sep 30",
        normalized="2026-09-30T16:59:00Z",
    )
    with pytest.raises(ReconciliationInputError):
        reconcile_field("submission_deadline", [report], [source])


def test_unknown_authority_basis_is_rejected() -> None:
    source = make_source("src-a", authority_rank={"basis": "banana"})
    report = make_report(
        "src-a",
        value="Sep 30",
        normalized="2026-09-30T16:59:00Z",
    )
    with pytest.raises(ReconciliationInputError):
        reconcile_field("submission_deadline", [report], [source])


def test_malformed_effective_at_is_rejected() -> None:
    source = make_source(
        "src-a",
        freshness_metadata={"effective_at": "garbage"},
    )
    report = make_report(
        "src-a",
        value="Sep 30",
        normalized="2026-09-30T16:59:00Z",
    )
    with pytest.raises(ReconciliationInputError):
        reconcile_field("submission_deadline", [report], [source])


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


def test_exact_duplicate_report_snapshot_is_rejected() -> None:
    source = make_source("src-a")
    report = make_report(
        "src-a",
        value="Sep 30",
        normalized="2026-09-30T16:59:00Z",
    )
    with pytest.raises(ReconciliationInputError):
        reconcile_field("submission_deadline", [report, report], [source])


def test_same_source_same_ocr_path_engine_disagreement_surfaces_conflict() -> None:
    source = make_source("src-a")
    reports = [
        make_report(
            "src-a",
            value="Sep 30",
            normalized="2026-09-30T16:59:00Z",
            path=ExtractionPath.OCR,
            evidence_id="ev-ocr-engine-a",
            extractor_version="ocr-engine-a:v1",
        ),
        make_report(
            "src-a",
            value="Oct 1",
            normalized="2026-10-01T16:59:00Z",
            path=ExtractionPath.OCR,
            evidence_id="ev-ocr-engine-b",
            extractor_version="ocr-engine-b:v1",
        ),
    ]
    result = reconcile_field("submission_deadline", reports, [source])
    assert result.canonical_field.state is CanonicalFieldState.CONFLICT


def test_same_source_same_ocr_path_agreement_still_counts_as_one_source() -> None:
    source = make_source("src-a")
    reports = [
        make_report(
            "src-a",
            value="Sep 30",
            normalized="2026-09-30T16:59:00Z",
            path=ExtractionPath.OCR,
            evidence_id="ev-ocr-engine-a",
            extractor_version="ocr-engine-a:v1",
        ),
        make_report(
            "src-a",
            value="September 30",
            normalized="2026-09-30T16:59:00Z",
            path=ExtractionPath.OCR,
            evidence_id="ev-ocr-engine-b",
            extractor_version="ocr-engine-b:v1",
        ),
    ]
    result = reconcile_field("submission_deadline", reports, [source])
    assert result.canonical_field.state is CanonicalFieldState.SINGLE_SOURCE
    assert result.supporting_source_ids == ("src-a",)


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
        effective_at="2026-09-20T00:00:00Z",
        supersedes=("src-old",),
        update_kind="extension",
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
        "submission_deadline",
        list(reversed(reports)),
        list(reversed(sources)),
    )
    assert forward == reverse
