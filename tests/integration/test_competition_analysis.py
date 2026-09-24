from __future__ import annotations

from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import pytest

from engine.extraction import (
    SourceContext,
    create_pdf_snapshot,
    extract_snapshot,
)
from engine.extraction.ocr import OCRTextBlock
from engine.integration import (
    READINESS_REQUIRED_FIELDS_V1,
    analyze_competition,
    build_canonical_report,
    build_readiness_request,
    resolve_eligibility_scope,
)
from engine.reconciliation import CANONICAL_V1, ReconciliationInputError
from packages.contracts import (
    CandidateField,
    CanonicalCompetitionReport,
    CanonicalField,
    CanonicalFieldState,
    ExtractionPath,
    ReadinessStatus,
    SourceType,
    UserContext,
)

NOW = datetime(2026, 9, 25, 0, 0, tzinfo=UTC)
FUTURE = NOW + timedelta(days=5)
FIXTURE_DIR = Path(__file__).parents[1] / "fixtures" / "extraction"


class _StaticOCRProvider:
    provider_id = "fixture-ocr"
    provider_version = "1"
    language = "eng"
    page_segmentation_mode = 6

    def __init__(self, text_by_page: dict[int, str]) -> None:
        self.text_by_page = text_by_page

    def extract_page(
        self,
        image_bytes: bytes,
        *,
        page_number: int,
        timeout_seconds: float,
    ) -> tuple[OCRTextBlock, ...]:
        del image_bytes, timeout_seconds
        text = self.text_by_page.get(page_number)
        if text is None:
            return ()
        return (
            OCRTextBlock(
                locator=f"page:{page_number}:fixture:1",
                text=text,
                page_number=page_number,
                confidence=0.99,
            ),
        )


def _source_context(source_id: str = "src-a") -> SourceContext:
    return SourceContext(
        source_id=source_id,
        source_type=SourceType.OFFICIAL_RULES,
        authority_rank={"basis": "official_rules", "tier": 1},
        scope={"category": "all"},
        freshness_metadata={
            "effective_at": "2026-09-01T00:00:00Z",
            "supersedes_source_ids": [],
        },
    )


def _candidate(
    field_name: str,
    value: Any,
    *,
    evidence_id: str,
) -> CandidateField:
    return CandidateField(
        field_name=field_name,
        raw_value=value,
        normalized_value=value,
        evidence_ids=[evidence_id],
        extraction_path=ExtractionPath.NATIVE,
        confidence=None,
        scope={"category": "all"},
    )


def _usable(
    field_name: str,
    value: Any,
    *,
    state: CanonicalFieldState = CanonicalFieldState.SINGLE_SOURCE,
) -> CanonicalField:
    evidence_id = f"ev-{field_name}"
    return CanonicalField(
        field_name=field_name,
        state=state,
        value=value,
        normalized_value=value,
        candidates=[_candidate(field_name, value, evidence_id=evidence_id)],
        evidence_ids=[evidence_id],
    )


def _missing(field_name: str) -> CanonicalField:
    return CanonicalField(
        field_name=field_name,
        state=CanonicalFieldState.MISSING,
    )


def _unverified(field_name: str, value: Any = "unknown") -> CanonicalField:
    evidence_id = f"ev-{field_name}-unverified"
    candidate = _candidate(field_name, value, evidence_id=evidence_id)
    return CanonicalField(
        field_name=field_name,
        state=CanonicalFieldState.UNVERIFIED,
        candidates=[candidate],
        evidence_ids=[evidence_id],
    )


def _conflict(field_name: str, left: Any, right: Any) -> CanonicalField:
    left_id = f"ev-{field_name}-left"
    right_id = f"ev-{field_name}-right"
    return CanonicalField(
        field_name=field_name,
        state=CanonicalFieldState.CONFLICT,
        candidates=[
            _candidate(field_name, left, evidence_id=left_id),
            _candidate(field_name, right, evidence_id=right_id),
        ],
        evidence_ids=[left_id, right_id],
    )


def _canonical_report(
    overrides: dict[str, CanonicalField] | None = None,
) -> CanonicalCompetitionReport:
    fields = {name: _missing(name) for name in CANONICAL_V1.core_fields}
    fields.update(
        {
            "submission_deadline": _usable(
                "submission_deadline",
                FUTURE.isoformat().replace("+00:00", "Z"),
            ),
            "eligibility": _usable(
                "eligibility",
                {
                    "minimum_age": 18,
                    "requires_student": True,
                    "allowed_regions": ["global"],
                },
            ),
            "deliverables": _usable("deliverables", ["demo"]),
        }
    )
    if overrides:
        fields.update(overrides)
    unresolved = [
        name
        for name in CANONICAL_V1.critical_fields
        if fields[name].state
        in {
            CanonicalFieldState.MISSING,
            CanonicalFieldState.CONFLICT,
            CanonicalFieldState.UNVERIFIED,
        }
    ]
    return CanonicalCompetitionReport(
        competition_id="cmp-1",
        report_version=1,
        source_ids=["src-a"],
        canonical_fields=fields,
        unresolved_critical_fields=unresolved,
    )


def _triage(report: CanonicalCompetitionReport, **kwargs):
    from engine.triage.service import evaluate_readiness

    request = build_readiness_request(
        canonical_report=report,
        user=kwargs.pop(
            "user",
            UserContext(age=21, student_status=True, country="Indonesia"),
        ),
        selected_scope=kwargs.pop("selected_scope", "unscoped"),
        evaluated_at=kwargs.pop("evaluated_at", NOW),
        require_technology_information=kwargs.pop(
            "require_technology_information",
            False,
        ),
    )
    assert not kwargs
    return request, evaluate_readiness(request)


def test_readiness_required_fields_v1_is_frozen_without_technology() -> None:
    assert READINESS_REQUIRED_FIELDS_V1 == (
        "submission_deadline",
        "eligibility",
        "deliverables",
    )


def test_deadline_missing_projects_to_insufficient_not_unresolved() -> None:
    report = _canonical_report(
        {"submission_deadline": _missing("submission_deadline")}
    )
    request, result = _triage(report)

    assert request.submission_deadline is None
    assert request.unresolved_critical_fields == []
    assert request.mandatory_information_complete is False
    assert result.status is ReadinessStatus.INSUFFICIENT_INFORMATION


@pytest.mark.parametrize(
    "field",
    [
        _conflict(
            "submission_deadline",
            "2026-09-28T00:00:00Z",
            "2026-09-30T00:00:00Z",
        ),
        _unverified("submission_deadline", "2026-09-30T00:00:00Z"),
    ],
)
def test_deadline_conflict_or_unverified_projects_to_review(field) -> None:
    report = _canonical_report({"submission_deadline": field})
    request, result = _triage(report)

    assert request.submission_deadline is None
    assert request.unresolved_critical_fields == ["submission_deadline"]
    assert result.status is ReadinessStatus.NEEDS_REVIEW


def test_eligibility_missing_projects_to_insufficient_information() -> None:
    report = _canonical_report({"eligibility": _missing("eligibility")})
    request, result = _triage(report)

    assert request.unresolved_critical_fields == []
    assert request.mandatory_information_complete is False
    assert result.status is ReadinessStatus.INSUFFICIENT_INFORMATION


def test_eligibility_conflict_projects_to_review() -> None:
    report = _canonical_report(
        {
            "eligibility": _conflict(
                "eligibility",
                {"minimum_age": 18},
                {"minimum_age": 21},
            )
        }
    )
    request, result = _triage(report)

    assert request.unresolved_critical_fields == ["eligibility"]
    assert result.status is ReadinessStatus.NEEDS_REVIEW


def test_deliverables_missing_projects_to_insufficient_information() -> None:
    report = _canonical_report({"deliverables": _missing("deliverables")})
    request, result = _triage(report)

    assert request.unresolved_critical_fields == []
    assert request.mandatory_information_complete is False
    assert result.status is ReadinessStatus.INSUFFICIENT_INFORMATION


def test_deliverables_conflict_projects_to_review() -> None:
    report = _canonical_report(
        {"deliverables": _conflict("deliverables", ["demo"], ["video"])}
    )
    request, result = _triage(report)

    assert request.unresolved_critical_fields == ["deliverables"]
    assert result.status is ReadinessStatus.NEEDS_REVIEW


def test_required_technologies_is_conditional_not_global() -> None:
    report = _canonical_report(
        {"required_technologies": _missing("required_technologies")}
    )

    default_request, default_result = _triage(report)
    required_request, required_result = _triage(
        report,
        require_technology_information=True,
    )

    assert default_request.mandatory_information_complete is True
    assert default_result.status is ReadinessStatus.READY_TO_EVALUATE
    assert required_request.mandatory_information_complete is False
    assert required_result.status is ReadinessStatus.INSUFFICIENT_INFORMATION


def test_unscoped_eligibility_reuses_existing_scope_model() -> None:
    report = _canonical_report()
    resolved = resolve_eligibility_scope(
        canonical_report=report,
        selected_scope="unscoped",
    )

    assert resolved is not None
    assert resolved.selected_scope == "unscoped"
    assert resolved.effective_rule.minimum_age == 18
    assert resolved.provenance


def test_scoped_eligibility_requires_explicit_matching_scope() -> None:
    variants = {
        "variants": [
            {
                "scope": {"audience": None, "category": "student", "region": None},
                "value": {
                    "minimum_age": 18,
                    "requires_student": True,
                    "allowed_regions": ["global"],
                },
            },
            {
                "scope": {
                    "audience": None,
                    "category": "professional",
                    "region": None,
                },
                "value": {
                    "minimum_age": 21,
                    "requires_student": False,
                    "allowed_regions": ["global"],
                },
            },
        ]
    }
    report = _canonical_report({"eligibility": _usable("eligibility", variants)})

    student = resolve_eligibility_scope(
        canonical_report=report,
        selected_scope="student_category",
    )
    missing_request, missing_result = _triage(report, selected_scope=None)
    invalid_request, invalid_result = _triage(report, selected_scope="banana")

    assert student is not None
    assert student.effective_rule.requires_student is True
    assert missing_request.unresolved_critical_fields == ["eligibility"]
    assert missing_result.status is ReadinessStatus.NEEDS_REVIEW
    assert invalid_request.unresolved_critical_fields == ["eligibility"]
    assert invalid_result.status is ReadinessStatus.NEEDS_REVIEW


def test_unknown_user_attribute_remains_review_not_blocked() -> None:
    report = _canonical_report()
    _, result = _triage(
        report,
        user=UserContext(age=None, student_status=True, country="Indonesia"),
    )
    assert result.status is ReadinessStatus.NEEDS_REVIEW


def test_known_eligibility_violation_is_blocked() -> None:
    report = _canonical_report()
    _, result = _triage(
        report,
        user=UserContext(age=17, student_status=True, country="Indonesia"),
    )
    assert result.status is ReadinessStatus.ELIGIBILITY_BLOCKED


def test_canonical_deadline_is_effective_and_extension_flag_is_false() -> None:
    extended = NOW + timedelta(days=10)
    report = _canonical_report(
        {
            "submission_deadline": _usable(
                "submission_deadline",
                extended.isoformat().replace("+00:00", "Z"),
            )
        }
    )
    request, result = _triage(report)

    assert request.submission_deadline == extended
    assert request.has_applicable_deadline_extension is False
    assert result.status is ReadinessStatus.READY_TO_EVALUATE


def test_date_less_exception_cannot_use_extension_backdoor() -> None:
    report = _canonical_report(
        {"submission_deadline": _unverified("submission_deadline", "late allowed")}
    )
    request, result = _triage(report)

    assert request.has_applicable_deadline_extension is False
    assert request.unresolved_critical_fields == ["submission_deadline"]
    assert result.status is ReadinessStatus.NEEDS_REVIEW


def test_canonical_unresolved_list_is_not_aliased_into_readiness_request() -> None:
    report = _canonical_report({"eligibility": _missing("eligibility")})
    assert report.unresolved_critical_fields == ["eligibility"]

    request, result = _triage(report)

    assert request.unresolved_critical_fields == []
    assert request.mandatory_information_complete is False
    assert result.status is ReadinessStatus.INSUFFICIENT_INFORMATION


def test_pipeline_001_reconciles_all_13_fields_from_one_pdf_snapshot() -> None:
    content = (FIXTURE_DIR / "native_competition.pdf").read_bytes()
    snapshot = create_pdf_snapshot(
        "fixture.pdf",
        content,
        context=_source_context(),
        retrieved_at=NOW,
    )
    extraction = extract_snapshot(
        snapshot,
        ocr_provider=_StaticOCRProvider(
            {2: "Submission deadline: September 30 2026 at 23:59 WIB"}
        ),
    )

    assembly = build_canonical_report(
        competition_id="cmp-pipeline",
        snapshot_results=[extraction],
    )

    assert tuple(
        result.canonical_field.field_name for result in assembly.field_results
    ) == CANONICAL_V1.core_fields
    assert len(assembly.field_results) == 13
    assert assembly.report.source_ids == ["src-a"]
    assert assembly.report.canonical_fields["submission_deadline"].state in {
        CanonicalFieldState.SINGLE_SOURCE,
        CanonicalFieldState.VERIFIED,
    }
    assert assembly.report.canonical_fields["eligibility"].state is CanonicalFieldState.MISSING


def test_pipeline_001_image_only_pdf_can_reach_canonical_from_ocr() -> None:
    content = (FIXTURE_DIR / "ocr_competition.pdf").read_bytes()
    snapshot = create_pdf_snapshot(
        "scan.pdf",
        content,
        context=_source_context("src-scan"),
        retrieved_at=NOW,
    )
    extraction = extract_snapshot(
        snapshot,
        ocr_provider=_StaticOCRProvider(
            {1: "Submission deadline: September 30 2026 at 23:59 WIB"}
        ),
    )
    assert extraction.native_document.blocks == ()

    assembly = build_canonical_report(
        competition_id="cmp-scan",
        snapshot_results=[extraction],
    )
    deadline = assembly.report.canonical_fields["submission_deadline"]
    assert deadline.state is CanonicalFieldState.SINGLE_SOURCE


def test_build_canonical_report_is_deterministic_for_same_snapshot() -> None:
    content = (FIXTURE_DIR / "native_competition.pdf").read_bytes()
    snapshot = create_pdf_snapshot(
        "fixture.pdf",
        content,
        context=_source_context(),
        retrieved_at=NOW,
    )
    extraction = extract_snapshot(
        snapshot,
        ocr_provider=_StaticOCRProvider({}),
    )

    first = build_canonical_report(
        competition_id="cmp-stable",
        snapshot_results=[extraction],
    )
    second = build_canonical_report(
        competition_id="cmp-stable",
        snapshot_results=[extraction],
        previous_report=first.report,
    )

    assert first.material_fingerprint == second.material_fingerprint
    assert second.report_changed is False
    assert second.report.report_version == first.report.report_version


def test_analyze_competition_keeps_raw_coverage_honest() -> None:
    content = (FIXTURE_DIR / "native_competition.pdf").read_bytes()
    snapshot = create_pdf_snapshot(
        "fixture.pdf",
        content,
        context=_source_context(),
        retrieved_at=NOW,
    )
    extraction = extract_snapshot(
        snapshot,
        ocr_provider=_StaticOCRProvider({}),
    )

    result = analyze_competition(
        competition_id="cmp-analysis",
        snapshot_results=[extraction],
        user=UserContext(age=21, student_status=True, country="Indonesia"),
        selected_scope="unscoped",
        evaluated_at=NOW,
    )

    eligibility = result.canonical_report.canonical_fields["eligibility"]
    assert eligibility.state is CanonicalFieldState.MISSING
    assert result.readiness.status is ReadinessStatus.INSUFFICIENT_INFORMATION
    assert result.readiness_request.mandatory_information_complete is False


def test_reconciliation_failure_propagates_instead_of_becoming_missing(monkeypatch) -> None:
    content = (FIXTURE_DIR / "native_competition.pdf").read_bytes()
    snapshot = create_pdf_snapshot(
        "fixture.pdf",
        content,
        context=_source_context(),
        retrieved_at=NOW,
    )
    extraction = extract_snapshot(
        snapshot,
        ocr_provider=_StaticOCRProvider({}),
    )

    def fail_reconcile(*args, **kwargs):
        del args, kwargs
        raise ReconciliationInputError("fixture failure")

    monkeypatch.setattr(
        "engine.integration.competition_analysis.reconcile_field",
        fail_reconcile,
    )

    with pytest.raises(ReconciliationInputError, match="fixture failure"):
        build_canonical_report(
            competition_id="cmp-failure",
            snapshot_results=[extraction],
        )


def test_mutated_invalid_canonical_report_is_rejected_at_projection_boundary() -> None:
    report = _canonical_report()
    deadline = report.canonical_fields["submission_deadline"]
    deadline.value = None
    deadline.normalized_value = None

    with pytest.raises(Exception) as exc_info:
        build_readiness_request(
            canonical_report=report,
            user=UserContext(age=21, student_status=True, country="Indonesia"),
            selected_scope="unscoped",
            evaluated_at=NOW,
        )

    assert exc_info.value.__class__.__name__ == "ValidationError"


def test_mutated_invalid_user_is_rejected_at_projection_boundary() -> None:
    user = UserContext(age=21, student_status=True, country="Indonesia")
    user.age = -5

    with pytest.raises(Exception) as exc_info:
        build_readiness_request(
            canonical_report=_canonical_report(),
            user=user,
            selected_scope="unscoped",
            evaluated_at=NOW,
        )

    assert exc_info.value.__class__.__name__ == "ValidationError"


@pytest.mark.parametrize("flag", ["false", 1, 0, None])
def test_technology_requirement_flag_requires_exact_bool(flag) -> None:
    with pytest.raises(TypeError, match="require_technology_information must be bool"):
        build_readiness_request(
            canonical_report=_canonical_report(),
            user=UserContext(age=21, student_status=True, country="Indonesia"),
            selected_scope="unscoped",
            evaluated_at=NOW,
            require_technology_information=flag,
        )


@pytest.mark.parametrize(
    "payload",
    [
        {},
        {"minimum_age": 18, "allowed_regions": ["global"]},
        {
            "minimum_age": 18,
            "requires_student": False,
            "requires_students": True,
            "allowed_regions": ["global"],
        },
        {
            "minimum_age": "18",
            "requires_student": False,
            "allowed_regions": ["global"],
        },
        {
            "minimum_age": 18,
            "requires_student": 1,
            "allowed_regions": ["global"],
        },
        {
            "minimum_age": 18,
            "requires_student": False,
            "allowed_regions": [""],
        },
    ],
)
def test_malformed_unscoped_eligibility_projects_to_review(payload) -> None:
    report = _canonical_report({"eligibility": _usable("eligibility", payload)})
    request, result = _triage(report)

    assert request.unresolved_critical_fields == ["eligibility"]
    assert result.status is ReadinessStatus.NEEDS_REVIEW


def test_explicit_complete_no_requirement_eligibility_is_valid() -> None:
    report = _canonical_report(
        {
            "eligibility": _usable(
                "eligibility",
                {
                    "minimum_age": None,
                    "requires_student": False,
                    "allowed_regions": [],
                },
            )
        }
    )
    request, result = _triage(report)

    assert request.unresolved_critical_fields == []
    assert request.eligibility.minimum_age is None
    assert request.eligibility.requires_student is False
    assert request.eligibility.allowed_regions == []
    assert result.status is ReadinessStatus.READY_TO_EVALUATE


@pytest.mark.parametrize(
    "payload",
    [
        {
            "variants": [
                {
                    "scope": {
                        "audience": None,
                        "category": "student",
                        "region": None,
                    },
                    "value": {
                        "minimum_age": 18,
                        "requires_student": True,
                        "allowed_regions": ["global"],
                    },
                }
            ],
            "extra": "x",
        },
        {
            "variants": [
                {
                    "scope": {
                        "audience": None,
                        "category": "student",
                        "region": None,
                    },
                    "value": {
                        "minimum_age": 18,
                        "requires_student": True,
                        "allowed_regions": ["global"],
                    },
                    "extra": "x",
                }
            ]
        },
        {
            "variants": [
                {
                    "scope": {
                        "audience": None,
                        "category": "student",
                        "region": None,
                        "weird": "x",
                    },
                    "value": {
                        "minimum_age": 18,
                        "requires_student": True,
                        "allowed_regions": ["global"],
                    },
                }
            ]
        },
    ],
)
def test_malformed_scoped_eligibility_projects_to_review(payload) -> None:
    report = _canonical_report({"eligibility": _usable("eligibility", payload)})
    request, result = _triage(report, selected_scope="student_category")

    assert request.unresolved_critical_fields == ["eligibility"]
    assert result.status is ReadinessStatus.NEEDS_REVIEW

def test_multidimensional_scope_cannot_be_resolved_by_one_selected_scope() -> None:
    variants = {
        "variants": [
            {
                "scope": {
                    "audience": None,
                    "category": "student",
                    "region": "US",
                },
                "value": {
                    "minimum_age": 18,
                    "requires_student": True,
                    "allowed_regions": ["global"],
                },
            }
        ]
    }
    report = _canonical_report({"eligibility": _usable("eligibility", variants)})

    resolved = resolve_eligibility_scope(
        canonical_report=report,
        selected_scope="student_category",
    )
    request, result = _triage(report, selected_scope="student_category")

    assert resolved is None
    assert request.unresolved_critical_fields == ["eligibility"]
    assert result.status is ReadinessStatus.NEEDS_REVIEW


def test_single_concrete_scope_dimension_still_resolves_with_wildcard_peer() -> None:
    variants = {
        "variants": [
            {
                "scope": {
                    "audience": None,
                    "category": "student",
                    "region": "all",
                },
                "value": {
                    "minimum_age": 18,
                    "requires_student": True,
                    "allowed_regions": ["global"],
                },
            }
        ]
    }
    report = _canonical_report({"eligibility": _usable("eligibility", variants)})

    resolved = resolve_eligibility_scope(
        canonical_report=report,
        selected_scope="student_category",
    )
    request, result = _triage(report, selected_scope="student_category")

    assert resolved is not None
    assert resolved.effective_rule.requires_student is True
    assert request.unresolved_critical_fields == []
    assert result.status is ReadinessStatus.READY_TO_EVALUATE

