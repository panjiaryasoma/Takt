"""Issue #4 release-facing backend regression matrix."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

import httpx
from fastapi.testclient import TestClient

import apps.api.services.competition_analysis as competition_analysis_service
from apps.api.contracts import (
    CompetitionAnalyzeUrlRequestV1,
    PlanEvaluatePlanningV1,
    PlanEvaluateRequestV1,
    PlanReevaluateRequestV1,
    PriorEvaluationBasisSnapshotV1,
    PriorEvaluationV1,
    ReadinessContextV1,
    ReadinessUserContextV1,
    SourceMetadataV1,
)
from apps.api.fingerprints import report_wire_fingerprint
from apps.api.main import app
from apps.api.services.competition_analysis import analyze_url
from apps.api.services.plan_evaluation import evaluate_plan
from apps.api.services.reevaluation import reevaluate_plan
from engine.extraction import (
    NativeDocument,
    NativeTextBlock,
    SnapshotBoundCandidateReport,
    SnapshotExtractionResult,
)
from packages.contracts import (
    AvailabilityInput,
    CandidateExtractionReport,
    CandidateField,
    CanonicalCompetitionReport,
    CanonicalField,
    CanonicalFieldState,
    EvidenceSpan,
    ExtractionPath,
    FeasibilityStatus,
    PlanningHorizon,
    PlanningPreferences,
    PlanningWorkWindow,
    ReadinessStatus,
    RecommendationAction,
    SourceType,
    Task,
    WorkloadInput,
)
from packages.contracts.source import CORE_CANONICAL_FIELDS

FIXED_CLOCK = datetime(2026, 9, 27, 13, 20, 17, tzinfo=UTC)
FIXED_EVALUATION_ID_1 = UUID("00000000-0000-4000-8000-000000000001")
FIXED_EVALUATION_ID_2 = UUID("00000000-0000-4000-8000-000000000002")
READY_DEADLINE = datetime(2026, 9, 30, 23, 45, tzinfo=UTC)

FORBIDDEN_PRODUCTION_FIXTURE_LITERALS = {
    "Synthetic Build Challenge",
    "Takt Fixture Hackathon",
    "cmp-entitlement-boundary",
    "cmp-ready",
}


def _clock() -> datetime:
    return FIXED_CLOCK


def _id_one() -> UUID:
    return FIXED_EVALUATION_ID_1


def _id_two() -> UUID:
    return FIXED_EVALUATION_ID_2


def _source_metadata() -> SourceMetadataV1:
    return SourceMetadataV1(
        source_id="src-issue4-regression",
        source_type=SourceType.OFFICIAL_RULES,
        authority_rank={"basis": "official_rules", "tier": 1},
        scope={"category": "all"},
        freshness_metadata={
            "effective_at": "2026-09-01T00:00:00Z",
            "supersedes_source_ids": [],
        },
    )


def _analysis_request() -> CompetitionAnalyzeUrlRequestV1:
    return CompetitionAnalyzeUrlRequestV1(
        competition_id="cmp-issue4-regression",
        url="https://example.test/issue4",
        source=_source_metadata(),
    )


def _evidence(
    *,
    source_id: str,
    field_name: str,
    raw_value,
) -> EvidenceSpan:
    return EvidenceSpan(
        evidence_id=f"ev-{field_name}",
        source_id=source_id,
        page_or_locator=f"html:body/{field_name}",
        raw_text_or_visual_reference=raw_value,
        field_name=field_name,
        extraction_path=ExtractionPath.NATIVE,
        extractor_version="issue4-regression-extractor-v1",
    )


def _candidate(
    *,
    field_name: str,
    raw_value,
    normalized_value,
) -> CandidateField:
    return CandidateField(
        field_name=field_name,
        raw_value=raw_value,
        normalized_value=normalized_value,
        evidence_ids=[f"ev-{field_name}"],
        extraction_path=ExtractionPath.NATIVE,
        confidence=1.0,
        scope={"category": "all"},
    )


def _deterministic_extraction(snapshot) -> SnapshotExtractionResult:
    source_id = snapshot.source_record.source_id
    deadline_raw = "September 30, 2026 at 23:45 UTC"
    eligibility_raw = "Open globally"
    deliverables_raw = ["demo"]

    report = CandidateExtractionReport(
        source_id=source_id,
        extraction_path=ExtractionPath.NATIVE,
        fields=[
            _candidate(
                field_name="submission_deadline",
                raw_value=deadline_raw,
                normalized_value=READY_DEADLINE,
            ),
            _candidate(
                field_name="eligibility",
                raw_value=eligibility_raw,
                normalized_value={
                    "minimum_age": None,
                    "requires_student": False,
                    "allowed_regions": ["global"],
                },
            ),
            _candidate(
                field_name="deliverables",
                raw_value=deliverables_raw,
                normalized_value=deliverables_raw,
            ),
        ],
        evidence=[
            _evidence(
                source_id=source_id,
                field_name="submission_deadline",
                raw_value=deadline_raw,
            ),
            _evidence(
                source_id=source_id,
                field_name="eligibility",
                raw_value=eligibility_raw,
            ),
            _evidence(
                source_id=source_id,
                field_name="deliverables",
                raw_value=deliverables_raw,
            ),
        ],
    )
    native = NativeDocument(
        source_record=snapshot.source_record,
        media_type=snapshot.media_type,
        raw_size_bytes=len(snapshot.content),
        blocks=(
            NativeTextBlock(
                locator="html:body",
                text=snapshot.content.decode("utf-8"),
                kind="body",
            ),
        ),
        retrieval=snapshot.origin_metadata,
        parser_version="issue4-regression-native-v1",
    )
    return SnapshotExtractionResult(
        snapshot=snapshot,
        native_document=native,
        ocr_document=None,
        bound_candidate_reports=(
            SnapshotBoundCandidateReport(
                snapshot_id=snapshot.snapshot_id,
                extraction_path=ExtractionPath.NATIVE,
                report=report,
            ),
        ),
    )


def _task(effort_minutes: int) -> Task:
    return Task(
        task_id="task-issue4",
        name="Build submission",
        mandatory=True,
        dependencies=(),
        effort_min_minutes=effort_minutes,
        effort_likely_minutes=effort_minutes,
        effort_max_minutes=effort_minutes,
        assumptions=("single-person estimate",),
    )


def _availability(*, end_hour: int = 15) -> AvailabilityInput:
    return AvailabilityInput(
        horizon=PlanningHorizon(
            start=datetime(2026, 9, 27, 12, 0, tzinfo=UTC),
            end=datetime(2026, 9, 27, end_hour, 0, tzinfo=UTC),
        ),
        work_windows=(
            PlanningWorkWindow(
                start=datetime(2026, 9, 27, 12, 0, tzinfo=UTC),
                end=datetime(2026, 9, 27, end_hour, 0, tzinfo=UTC),
            ),
        ),
        preferences=PlanningPreferences(
            timezone="UTC",
            max_project_minutes_per_day=480,
            preferred_focus_minutes=60,
            buffer_target_minutes=0,
        ),
    )


def _evaluation_request(
    report_bundle,
    *,
    effort_minutes: int = 60,
    availability: AvailabilityInput | None = None,
) -> PlanEvaluateRequestV1:
    return PlanEvaluateRequestV1(
        report_bundle=report_bundle,
        readiness_context=ReadinessContextV1(
            user=ReadinessUserContextV1(),
            selected_scope="unscoped",
            require_technology_information=False,
        ),
        planning=PlanEvaluatePlanningV1(
            workload=WorkloadInput(tasks=(_task(effort_minutes),)),
            availability=availability or _availability(),
        ),
    )


def _canonical_field(
    field_name: str,
    *,
    raw_value,
    normalized_value,
) -> CanonicalField:
    candidate = _candidate(
        field_name=field_name,
        raw_value=raw_value,
        normalized_value=normalized_value,
    )
    return CanonicalField(
        field_name=field_name,
        state=CanonicalFieldState.SINGLE_SOURCE,
        value=raw_value,
        normalized_value=normalized_value,
        candidates=[candidate],
        evidence_ids=list(candidate.evidence_ids),
    )


def _canonical_report(
    *,
    deadline: datetime = READY_DEADLINE,
    conflict_eligibility: bool = False,
) -> CanonicalCompetitionReport:
    fields = {
        name: CanonicalField(field_name=name, state=CanonicalFieldState.MISSING)
        for name in CORE_CANONICAL_FIELDS
    }
    fields["submission_deadline"] = _canonical_field(
        "submission_deadline",
        raw_value="September 30, 2026 at 23:45 UTC",
        normalized_value=deadline,
    )
    fields["deliverables"] = _canonical_field(
        "deliverables",
        raw_value=["demo"],
        normalized_value=["demo"],
    )

    unresolved: list[str] = []
    if conflict_eligibility:
        first = _candidate(
            field_name="eligibility",
            raw_value="Open globally",
            normalized_value={
                "minimum_age": None,
                "requires_student": False,
                "allowed_regions": ["global"],
            },
        )
        second = CandidateField(
            field_name="eligibility",
            raw_value="Students only",
            normalized_value={
                "minimum_age": None,
                "requires_student": True,
                "allowed_regions": ["global"],
            },
            evidence_ids=["ev-eligibility-conflict"],
            extraction_path=ExtractionPath.NATIVE,
            confidence=1.0,
            scope={"category": "all"},
        )
        fields["eligibility"] = CanonicalField(
            field_name="eligibility",
            state=CanonicalFieldState.CONFLICT,
            candidates=[first, second],
            evidence_ids=[
                *first.evidence_ids,
                *second.evidence_ids,
            ],
        )
        unresolved.append("eligibility")
    else:
        fields["eligibility"] = _canonical_field(
            "eligibility",
            raw_value="Open globally",
            normalized_value={
                "minimum_age": None,
                "requires_student": False,
                "allowed_regions": ["global"],
            },
        )

    return CanonicalCompetitionReport(
        competition_id="cmp-issue4-regression",
        report_version=1,
        source_ids=["src-issue4-regression"],
        canonical_fields=fields,
        unresolved_critical_fields=unresolved,
    )


def _bundle(report: CanonicalCompetitionReport):
    from apps.api.contracts import CanonicalReportBundleV1, CanonicalReportRefV1

    initial = CanonicalReportRefV1(
        competition_id=report.competition_id,
        report_version=report.report_version,
        assembly_material_fingerprint="b" * 64,
        wire_fingerprint="0" * 64,
    )
    ref = initial.model_copy(
        update={"wire_fingerprint": report_wire_fingerprint(report, initial)}
    )
    return CanonicalReportBundleV1(report=report, ref=ref)


def _analysis_to_evaluation(monkeypatch):
    html = b"<html><body>Issue 4 deterministic source</body></html>"

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html"},
            content=html,
            request=request,
        )

    monkeypatch.setattr(
        "engine.extraction.native.validate_public_http_target",
        lambda _url: None,
    )
    monkeypatch.setattr(
        competition_analysis_service,
        "extract_snapshot",
        _deterministic_extraction,
    )
    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        analysis = analyze_url(_analysis_request(), client=client)

    request = _evaluation_request(analysis.report_bundle)
    evaluation = evaluate_plan(
        request,
        clock=_clock,
        evaluation_id_factory=_id_one,
    )
    return analysis, request, evaluation


def test_issue4_happy_path_regression(monkeypatch) -> None:
    analysis, _, evaluation = _analysis_to_evaluation(monkeypatch)

    assert analysis.report_changed is True
    assert evaluation.readiness.status is ReadinessStatus.READY_TO_EVALUATE
    assert evaluation.planning is not None
    assert evaluation.planning.feasibility is FeasibilityStatus.FEASIBLE
    assert evaluation.planning.candidates
    assert evaluation.planning.recommendation is not None

    candidate_ids = {
        candidate.ref.candidate_id for candidate in evaluation.planning.candidates
    }
    recommendation = evaluation.planning.recommendation
    referenced_ids = {
        recommendation.primary_candidate.candidate_id,
        *(
            item.candidate_id
            for item in recommendation.alternative_candidates
        ),
    }
    assert referenced_ids <= candidate_ids

    report_ref = analysis.report_bundle.ref
    assert evaluation.basis.report.competition_id == report_ref.competition_id
    assert evaluation.basis.report.report_version == report_ref.report_version
    assert recommendation.trace.competition_id == report_ref.competition_id
    assert recommendation.trace.report_version == report_ref.report_version
    assert (
        recommendation.trace.evaluation_basis_fingerprint
        == evaluation.basis.fingerprint
    )
    assert evaluation.basis.planning is not None
    assert (
        recommendation.trace.planning_basis_fingerprint
        == evaluation.basis.planning.basis_fingerprint
    )


def test_issue4_conflict_path_regression() -> None:
    report = _canonical_report(conflict_eligibility=True)
    evaluation = evaluate_plan(
        _evaluation_request(_bundle(report)),
        clock=_clock,
        evaluation_id_factory=_id_one,
    )

    assert report.canonical_fields["eligibility"].state is CanonicalFieldState.CONFLICT
    assert evaluation.readiness.status is ReadinessStatus.NEEDS_REVIEW
    assert evaluation.planning is None
    assert evaluation.basis.planning is None
    assert "unresolved_critical_field:eligibility" in evaluation.readiness.review_items


def test_issue4_infeasible_path_regression() -> None:
    request = _evaluation_request(
        _bundle(_canonical_report()),
        effort_minutes=200,
    )
    response = TestClient(app).post(
        "/api/v1/plans/evaluate",
        json=request.model_dump(mode="json", warnings=False),
    )

    assert response.status_code == 200
    body = response.json()
    assert (
        body["planning"]["feasibility"]
        == FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS.value
    )
    assert body["planning"]["candidates"] == []
    assert body["planning"]["recommendation"] is None
    assert body["planning"]["allowed_actions"] == [
        RecommendationAction.EDIT_CONSTRAINTS.value,
        RecommendationAction.IGNORE.value,
    ]


def test_issue4_stale_reevaluation_regression() -> None:
    initial_request = _evaluation_request(_bundle(_canonical_report()))
    prior = evaluate_plan(
        initial_request,
        clock=_clock,
        evaluation_id_factory=_id_one,
    )
    changed_request = initial_request.model_copy(
        update={
            "planning": initial_request.planning.model_copy(
                update={"availability": _availability(end_hour=14)}
            )
        }
    )
    prior_basis = PriorEvaluationBasisSnapshotV1.model_validate(
        prior.basis.model_dump(mode="json", warnings=False)
    )
    request = PlanReevaluateRequestV1(
        prior=PriorEvaluationV1(
            evaluation_id=prior.evaluation_id,
            basis=prior_basis,
        ),
        current=changed_request,
    )

    result = reevaluate_plan(
        request,
        clock=_clock,
        evaluation_id_factory=_id_two,
    )

    assert result.transition.kind == "SUPERSEDED"
    assert result.transition.prior_evaluation_freshness == "STALE"
    assert result.transition.change_reasons == ("PLANNING_BASIS_CHANGED",)
    assert result.evaluation is not None
    fresh = result.evaluation
    assert fresh.evaluation_id != prior.evaluation_id
    assert fresh.basis.fingerprint != prior.basis.fingerprint
    assert result.transition.current_basis_fingerprint == fresh.basis.fingerprint

    assert fresh.planning is not None
    recommendation = fresh.planning.recommendation
    assert recommendation is not None
    assert recommendation.trace.competition_id == fresh.basis.report.competition_id
    assert recommendation.trace.report_version == fresh.basis.report.report_version
    assert recommendation.trace.evaluation_basis_fingerprint == fresh.basis.fingerprint
    assert fresh.basis.planning is not None
    assert (
        recommendation.trace.planning_basis_fingerprint
        == fresh.basis.planning.basis_fingerprint
    )


def test_issue4_outputs_are_input_sensitive_not_demo_constants() -> None:
    feasible = evaluate_plan(
        _evaluation_request(_bundle(_canonical_report())),
        clock=_clock,
        evaluation_id_factory=_id_one,
    )
    conflict = evaluate_plan(
        _evaluation_request(_bundle(_canonical_report(conflict_eligibility=True))),
        clock=_clock,
        evaluation_id_factory=_id_one,
    )
    infeasible = evaluate_plan(
        _evaluation_request(
            _bundle(_canonical_report()),
            effort_minutes=200,
        ),
        clock=_clock,
        evaluation_id_factory=_id_one,
    )
    expired = evaluate_plan(
        _evaluation_request(
            _bundle(
                _canonical_report(
                    deadline=datetime(2026, 9, 27, 12, 0, tzinfo=UTC),
                )
            )
        ),
        clock=_clock,
        evaluation_id_factory=_id_one,
    )

    states = (
        (
            feasible.readiness.status,
            feasible.planning.feasibility if feasible.planning else None,
        ),
        (
            conflict.readiness.status,
            conflict.planning.feasibility if conflict.planning else None,
        ),
        (
            infeasible.readiness.status,
            infeasible.planning.feasibility if infeasible.planning else None,
        ),
        (
            expired.readiness.status,
            expired.planning.feasibility if expired.planning else None,
        ),
    )
    assert states == (
        (ReadinessStatus.READY_TO_EVALUATE, FeasibilityStatus.FEASIBLE),
        (ReadinessStatus.NEEDS_REVIEW, None),
        (
            ReadinessStatus.READY_TO_EVALUATE,
            FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS,
        ),
        (ReadinessStatus.DEADLINE_PASSED, None),
    )


def test_issue4_production_has_no_known_fixture_answers() -> None:
    repository_root = Path(__file__).resolve().parents[2]
    production_roots = (
        repository_root / "apps",
        repository_root / "engine",
        repository_root / "packages",
    )

    leaks: list[str] = []
    for root in production_roots:
        for path in root.rglob("*.py"):
            content = path.read_text(encoding="utf-8")
            for literal in FORBIDDEN_PRODUCTION_FIXTURE_LITERALS:
                if literal in content:
                    leaks.append(
                        f"{path.relative_to(repository_root)} contains {literal!r}"
                    )

    assert leaks == []
