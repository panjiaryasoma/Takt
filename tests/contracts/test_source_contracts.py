from datetime import UTC, datetime

import pytest
from pydantic import ValidationError

from packages.contracts import (
    CandidateExtractionReport,
    CandidateField,
    CanonicalCompetitionReport,
    CanonicalField,
    CanonicalFieldState,
    EvidenceSpan,
    ExtractionPath,
    SourceRecord,
    SourceType,
)

NOW = datetime(2026, 9, 23, 8, 0, tzinfo=UTC)

CORE_FIELDS = {
    "competition_name",
    "organizer",
    "submission_deadline",
    "registration_deadline",
    "eligibility",
    "team_size",
    "format",
    "location",
    "tracks_or_categories",
    "deliverables",
    "required_technologies",
    "judging_criteria",
    "prizes_or_benefits",
}


def make_evidence(
    evidence_id: str = "ev_001",
    *,
    field_name: str = "submission_deadline",
    source_id: str = "src_001",
    path: ExtractionPath = ExtractionPath.NATIVE,
) -> EvidenceSpan:
    return EvidenceSpan(
        evidence_id=evidence_id,
        source_id=source_id,
        page_or_locator="page:4/section:submission-deadline",
        raw_text_or_visual_reference="Deadline is September 30 at 23:59 WIB",
        field_name=field_name,
        extraction_path=path,
        extractor_version="1.0.0",
    )


def make_candidate(
    *,
    raw_value="2026-09-30T23:59:00+07:00",
    normalized_value="2026-09-30T16:59:00Z",
    evidence_id="ev_001",
    field_name="submission_deadline",
    path: ExtractionPath = ExtractionPath.NATIVE,
    confidence: float | None = 0.92,
) -> CandidateField:
    return CandidateField(
        field_name=field_name,
        raw_value=raw_value,
        normalized_value=normalized_value,
        evidence_ids=[evidence_id],
        extraction_path=path,
        confidence=confidence,
        scope={"category": "general"},
    )


def make_missing_field(field_name: str) -> CanonicalField:
    return CanonicalField(
        field_name=field_name,
        state=CanonicalFieldState.MISSING,
    )


def make_complete_core_fields(
    *,
    deadline_field: CanonicalField | None = None,
) -> dict[str, CanonicalField]:
    fields = {name: make_missing_field(name) for name in CORE_FIELDS}
    if deadline_field is not None:
        fields["submission_deadline"] = deadline_field
    return fields


def test_source_enum_wire_values_match_source_schema() -> None:
    assert [item.value for item in SourceType] == [
        "official_rules",
        "official_organizer",
        "official_faq",
        "platform",
        "secondary",
        "derived_fixture",
    ]
    assert [item.value for item in ExtractionPath] == [
        "native",
        "ocr",
        "vision",
        "manual",
    ]


def test_source_record_matches_required_source_schema_shape() -> None:
    record = SourceRecord(
        source_id="src_001",
        source_type=SourceType.OFFICIAL_RULES,
        url_or_document_id="https://example.test/rules.pdf",
        retrieved_at=NOW,
        content_hash="sha-any-algorithm-contract-does-not-pin-one",
        authority_rank={"kind": "official_rules"},
        scope={"category": "general"},
        freshness_metadata={"published_at": "2026-09-20T00:00:00Z"},
    )

    payload = record.model_dump(mode="json")
    assert payload["source_type"] == "official_rules"
    assert payload["url_or_document_id"] == "https://example.test/rules.pdf"
    assert payload["content_hash"] == "sha-any-algorithm-contract-does-not-pin-one"


def test_source_record_requires_all_official_fields() -> None:
    with pytest.raises(ValidationError):
        SourceRecord(
            source_id="src_001",
            source_type=SourceType.OFFICIAL_RULES,
            url_or_document_id="rules.pdf",
            retrieved_at=NOW,
            content_hash="abc",
            authority_rank={"kind": "official_rules"},
            scope={"category": "general"},
            # freshness_metadata sengaja hilang
        )


def test_source_record_rejects_null_required_reconciliation_metadata() -> None:
    base = {
        "source_id": "src_001",
        "source_type": SourceType.OFFICIAL_RULES,
        "url_or_document_id": "rules.pdf",
        "retrieved_at": NOW,
        "content_hash": "abc",
        "authority_rank": {},
        "scope": {},
        "freshness_metadata": {},
    }

    for field_name in ("authority_rank", "scope", "freshness_metadata"):
        payload = {**base, field_name: None}
        with pytest.raises(ValidationError):
            SourceRecord(**payload)


def test_source_record_allows_explicit_unknown_metadata_without_inventing_shape() -> None:
    record = SourceRecord(
        source_id="src_001",
        source_type=SourceType.OFFICIAL_RULES,
        url_or_document_id="rules.pdf",
        retrieved_at=NOW,
        content_hash="abc",
        authority_rank={},
        scope={},
        freshness_metadata={},
    )

    assert record.authority_rank == {}
    assert record.scope == {}
    assert record.freshness_metadata == {}


def test_source_record_rejects_naive_retrieved_at() -> None:
    with pytest.raises(ValidationError):
        SourceRecord(
            source_id="src_001",
            source_type=SourceType.OFFICIAL_RULES,
            url_or_document_id="rules.pdf",
            retrieved_at="2026-09-23T08:00:00",
            content_hash="abc",
            authority_rank={"kind": "official_rules"},
            scope={"category": "general"},
            freshness_metadata={},
        )


def test_source_record_does_not_invent_sha256_requirement() -> None:
    record = SourceRecord(
        source_id="src_001",
        source_type=SourceType.OFFICIAL_RULES,
        url_or_document_id="rules.pdf",
        retrieved_at=NOW,
        content_hash="not-64-hex-but-still-a-non-empty-contract-value",
        authority_rank={"kind": "official_rules"},
        scope={"category": "general"},
        freshness_metadata={},
    )
    assert record.content_hash.startswith("not-64")


def test_contract_models_reject_unknown_fields() -> None:
    with pytest.raises(ValidationError):
        SourceRecord(
            source_id="src_001",
            source_type=SourceType.OFFICIAL_RULES,
            url_or_document_id="rules.pdf",
            retrieved_at=NOW,
            content_hash="abc",
            authority_rank={"kind": "official_rules"},
            scope={},
            freshness_metadata={},
            made_up_field="must fail",
        )


def test_evidence_span_matches_source_schema_shape() -> None:
    evidence = make_evidence()
    payload = evidence.model_dump(mode="json")

    assert set(payload) == {
        "evidence_id",
        "source_id",
        "page_or_locator",
        "raw_text_or_visual_reference",
        "field_name",
        "extraction_path",
        "extractor_version",
    }
    assert payload["extraction_path"] == "native"


def test_evidence_span_allows_manual_path_but_candidate_does_not() -> None:
    manual = make_evidence(path=ExtractionPath.MANUAL)
    assert manual.extraction_path is ExtractionPath.MANUAL

    with pytest.raises(ValidationError):
        make_candidate(path=ExtractionPath.MANUAL)


def test_candidate_field_uses_official_shape_and_optional_confidence() -> None:
    candidate = make_candidate(confidence=None)
    payload = candidate.model_dump(mode="json")

    assert set(payload) == {
        "field_name",
        "raw_value",
        "normalized_value",
        "evidence_ids",
        "extraction_path",
        "confidence",
        "scope",
    }
    assert payload["confidence"] is None


def test_candidate_field_confidence_is_bounded_when_present() -> None:
    with pytest.raises(ValidationError):
        make_candidate(confidence=1.1)


def test_candidate_field_rejects_null_scope() -> None:
    with pytest.raises(ValidationError):
        CandidateField(
            field_name="submission_deadline",
            raw_value="Sep 30",
            normalized_value="2026-09-30T16:59:00Z",
            evidence_ids=["ev_001"],
            extraction_path=ExtractionPath.NATIVE,
            confidence=None,
            scope=None,
        )


def test_candidate_field_requires_scope_and_evidence_ids() -> None:
    with pytest.raises(ValidationError):
        CandidateField(
            field_name="submission_deadline",
            raw_value="Sep 30",
            normalized_value="2026-09-30T16:59:00Z",
            evidence_ids=[],
            extraction_path=ExtractionPath.NATIVE,
            confidence=None,
            scope={},
        )

    with pytest.raises(ValidationError):
        CandidateField(
            field_name="submission_deadline",
            raw_value="Sep 30",
            normalized_value="2026-09-30T16:59:00Z",
            evidence_ids=["ev_001"],
            extraction_path=ExtractionPath.NATIVE,
            confidence=None,
            # scope sengaja hilang
        )


def test_candidate_report_provenance_is_traceable_and_path_consistent() -> None:
    evidence = make_evidence()
    candidate = make_candidate()
    report = CandidateExtractionReport(
        source_id="src_001",
        extraction_path=ExtractionPath.NATIVE,
        fields=[candidate],
        evidence=[evidence],
    )

    assert report.fields[0].evidence_ids == ["ev_001"]
    assert report.evidence[0].source_id == "src_001"


def test_candidate_report_rejects_missing_evidence_reference() -> None:
    with pytest.raises(ValidationError):
        CandidateExtractionReport(
            source_id="src_001",
            extraction_path=ExtractionPath.NATIVE,
            fields=[make_candidate(evidence_id="ev_missing")],
            evidence=[make_evidence()],
        )


def test_candidate_report_rejects_cross_source_evidence() -> None:
    with pytest.raises(ValidationError):
        CandidateExtractionReport(
            source_id="src_001",
            extraction_path=ExtractionPath.NATIVE,
            fields=[make_candidate()],
            evidence=[make_evidence(source_id="src_other")],
        )


def test_native_and_ocr_reports_share_the_same_schema() -> None:
    native = CandidateExtractionReport(
        source_id="src_001",
        extraction_path=ExtractionPath.NATIVE,
        fields=[make_candidate(path=ExtractionPath.NATIVE)],
        evidence=[make_evidence(path=ExtractionPath.NATIVE)],
    )
    ocr = CandidateExtractionReport(
        source_id="src_001",
        extraction_path=ExtractionPath.OCR,
        fields=[
            make_candidate(
                path=ExtractionPath.OCR,
                evidence_id="ev_ocr",
            )
        ],
        evidence=[
            make_evidence(
                evidence_id="ev_ocr",
                path=ExtractionPath.OCR,
            )
        ],
    )

    assert set(native.model_dump()) == set(ocr.model_dump())
    assert "state" not in native.model_dump()


def test_verified_and_single_source_require_real_provenance() -> None:
    with pytest.raises(ValidationError):
        CanonicalField(
            field_name="submission_deadline",
            state=CanonicalFieldState.VERIFIED,
            value="Sep 30",
            normalized_value="2026-09-30T16:59:00Z",
            candidates=[],
            evidence_ids=[],
        )

    candidate = make_candidate()
    valid = CanonicalField(
        field_name="submission_deadline",
        state=CanonicalFieldState.SINGLE_SOURCE,
        value="Sep 30",
        normalized_value="2026-09-30T16:59:00Z",
        candidates=[candidate],
        evidence_ids=["ev_001"],
    )
    assert valid.state is CanonicalFieldState.SINGLE_SOURCE


def test_canonical_field_rejects_dropped_candidate_provenance() -> None:
    with pytest.raises(ValidationError):
        CanonicalField(
            field_name="submission_deadline",
            state=CanonicalFieldState.SINGLE_SOURCE,
            value="Sep 30",
            normalized_value="2026-09-30T16:59:00Z",
            candidates=[make_candidate()],
            evidence_ids=["ev_other"],
        )


def test_conflict_requires_two_actual_disagreeing_candidates_and_no_value() -> None:
    first = make_candidate(evidence_id="ev_001")
    second = make_candidate(
        raw_value="2026-10-01T23:59:00+07:00",
        normalized_value="2026-10-01T16:59:00Z",
        evidence_id="ev_002",
    )

    conflict = CanonicalField(
        field_name="submission_deadline",
        state=CanonicalFieldState.CONFLICT,
        candidates=[first, second],
        evidence_ids=["ev_001", "ev_002"],
    )
    assert conflict.value is None

    with pytest.raises(ValidationError):
        CanonicalField(
            field_name="submission_deadline",
            state=CanonicalFieldState.CONFLICT,
            candidates=[first],
            evidence_ids=["ev_001"],
        )

    with pytest.raises(ValidationError):
        CanonicalField(
            field_name="submission_deadline",
            state=CanonicalFieldState.CONFLICT,
            value="Sep 30",
            normalized_value="2026-09-30T16:59:00Z",
            candidates=[first, second],
            evidence_ids=["ev_001", "ev_002"],
        )


def test_conflict_uses_normalized_value_not_raw_spelling() -> None:
    first = make_candidate(
        raw_value="Sep 30",
        normalized_value="2026-09-30",
        evidence_id="ev_001",
    )
    same_meaning = make_candidate(
        raw_value="September 30",
        normalized_value="2026-09-30",
        evidence_id="ev_002",
    )

    with pytest.raises(ValidationError):
        CanonicalField(
            field_name="submission_deadline",
            state=CanonicalFieldState.CONFLICT,
            candidates=[first, same_meaning],
            evidence_ids=["ev_001", "ev_002"],
        )


def test_missing_is_explicit_and_cannot_hide_a_candidate() -> None:
    missing = make_missing_field("organizer")
    assert missing.value is None
    assert missing.candidates == []

    with pytest.raises(ValidationError):
        CanonicalField(
            field_name="organizer",
            state=CanonicalFieldState.MISSING,
            candidates=[
                make_candidate(
                    field_name="organizer",
                    raw_value="Org",
                    normalized_value="Org",
                )
            ],
            evidence_ids=["ev_001"],
        )


def test_unverified_keeps_candidate_but_exposes_no_canonical_value() -> None:
    candidate = make_candidate()
    unverified = CanonicalField(
        field_name="submission_deadline",
        state=CanonicalFieldState.UNVERIFIED,
        candidates=[candidate],
        evidence_ids=["ev_001"],
    )
    assert unverified.value is None


def test_canonical_report_requires_every_core_field_even_when_missing() -> None:
    with pytest.raises(ValidationError):
        CanonicalCompetitionReport(
            competition_id="cmp_001",
            report_version=1,
            source_ids=["src_001"],
            canonical_fields={
                "submission_deadline": make_missing_field("submission_deadline")
            },
            unresolved_critical_fields=["submission_deadline"],
        )

    report = CanonicalCompetitionReport(
        competition_id="cmp_001",
        report_version=1,
        source_ids=["src_001"],
        canonical_fields=make_complete_core_fields(),
        unresolved_critical_fields=["submission_deadline"],
    )
    assert set(report.canonical_fields) == CORE_FIELDS


def test_unresolved_critical_fields_must_reference_unresolved_state() -> None:
    candidate = make_candidate()
    resolved_deadline = CanonicalField(
        field_name="submission_deadline",
        state=CanonicalFieldState.SINGLE_SOURCE,
        value="Sep 30",
        normalized_value="2026-09-30T16:59:00Z",
        candidates=[candidate],
        evidence_ids=["ev_001"],
    )

    with pytest.raises(ValidationError):
        CanonicalCompetitionReport(
            competition_id="cmp_001",
            report_version=1,
            source_ids=["src_001"],
            canonical_fields=make_complete_core_fields(deadline_field=resolved_deadline),
            unresolved_critical_fields=["submission_deadline"],
        )


def test_noncritical_conflict_is_not_automatically_marked_critical() -> None:
    first = make_candidate(
        field_name="prizes_or_benefits",
        raw_value="$5000",
        normalized_value=5000,
        evidence_id="ev_001",
    )
    second = make_candidate(
        field_name="prizes_or_benefits",
        raw_value="$5500",
        normalized_value=5500,
        evidence_id="ev_002",
    )
    prize_conflict = CanonicalField(
        field_name="prizes_or_benefits",
        state=CanonicalFieldState.CONFLICT,
        candidates=[first, second],
        evidence_ids=["ev_001", "ev_002"],
    )

    fields = make_complete_core_fields()
    fields["prizes_or_benefits"] = prize_conflict

    report = CanonicalCompetitionReport(
        competition_id="cmp_001",
        report_version=1,
        source_ids=["src_001", "src_002"],
        canonical_fields=fields,
        unresolved_critical_fields=[],
    )
    assert report.canonical_fields["prizes_or_benefits"].state is CanonicalFieldState.CONFLICT


def test_canonical_report_rejects_field_key_mismatch() -> None:
    fields = make_complete_core_fields()
    fields["submission_deadline"] = CanonicalField(
        field_name="organizer",
        state=CanonicalFieldState.MISSING,
    )

    with pytest.raises(ValidationError):
        CanonicalCompetitionReport(
            competition_id="cmp_001",
            report_version=1,
            source_ids=["src_001"],
            canonical_fields=fields,
            unresolved_critical_fields=[],
        )
