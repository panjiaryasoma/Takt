"""Block 3 guard tests: monetization must not become correctness authority."""

from __future__ import annotations

import inspect
from datetime import UTC, datetime
from uuid import UUID

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from apps.api.contracts import (
    CanonicalReportBundleV1,
    CanonicalReportRefV1,
    CompetitionAnalyzePdfMetadataV1,
    CompetitionAnalyzeUrlRequestV1,
    EvaluationBasisV1,
    PlanEvaluatePlanningV1,
    PlanEvaluateRequestV1,
    PlanningBasisV1,
    PlanReevaluateRequestV1,
    PriorEvaluationBasisSnapshotV1,
    PriorEvaluationV1,
    ReadinessBasisV1,
    ReadinessContextV1,
    ReadinessUserContextV1,
    ReportBasisV1,
    SourceMetadataV1,
)
from apps.api.fingerprints import report_wire_fingerprint
from apps.api.main import app
from apps.api.policy_versions import PLANNING_POLICY
from apps.api.services.plan_evaluation import evaluate_plan
from engine.feasibility.service import assess_feasibility_run
from engine.integration.competition_analysis import build_readiness_request
from engine.recommendation.service import build_recommendation
from engine.reconciliation import reconcile_field
from engine.scheduler.models import SolverConfig
from engine.scheduler.service import _MAX_CANDIDATES, solve_candidate_allocations
from engine.triage.service import evaluate_readiness
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
    ReadinessRequest,
    ReadinessStatus,
    SourceRecord,
    SourceType,
    Task,
    UserContext,
    WorkloadInput,
)
from packages.contracts.source import CORE_CANONICAL_FIELDS

_MONETIZATION_NAMES = {
    "entitlement",
    "entitlements",
    "is_premium",
    "premium",
    "premium_features",
    "revenuecat",
    "revenuecat_customer",
    "subscription",
    "subscription_tier",
    "tier",
}


def _ready_report(
    *,
    deadline: datetime | None = None,
    required_technologies: list[str] | None = None,
) -> CanonicalCompetitionReport:
    deadline = deadline or datetime(2026, 9, 30, 23, 45, tzinfo=UTC)
    fields = {
        name: CanonicalField(field_name=name, state=CanonicalFieldState.MISSING)
        for name in CORE_CANONICAL_FIELDS
    }
    fields["submission_deadline"] = _canonical_field(
        "submission_deadline",
        value="September 30, 2026 at 23:45 UTC",
        normalized=deadline,
    )
    fields["eligibility"] = _canonical_field(
        "eligibility",
        value="Open globally",
        normalized={
            "minimum_age": None,
            "requires_student": False,
            "allowed_regions": ["global"],
        },
    )
    fields["deliverables"] = _canonical_field(
        "deliverables",
        value=["demo"],
        normalized=["demo"],
    )
    if required_technologies is not None:
        fields["required_technologies"] = _canonical_field(
            "required_technologies",
            value=required_technologies,
            normalized=required_technologies,
        )
    return CanonicalCompetitionReport(
        competition_id="cmp-entitlement-boundary",
        report_version=1,
        source_ids=["src-official"],
        canonical_fields=fields,
        unresolved_critical_fields=[],
    )


def _canonical_field(
    field_name: str,
    *,
    value,
    normalized,
) -> CanonicalField:
    evidence_id = f"ev-{field_name}"
    candidate = CandidateField(
        field_name=field_name,
        raw_value=value,
        normalized_value=normalized,
        evidence_ids=[evidence_id],
        extraction_path=ExtractionPath.NATIVE,
        confidence=None,
        scope={},
    )
    return CanonicalField(
        field_name=field_name,
        state=CanonicalFieldState.SINGLE_SOURCE,
        value=value,
        normalized_value=normalized,
        candidates=[candidate],
        evidence_ids=[evidence_id],
    )


def _report_bundle(report: CanonicalCompetitionReport) -> CanonicalReportBundleV1:
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


def _plan_request(*, effort_minutes: int = 60) -> PlanEvaluateRequestV1:
    task = Task(
        task_id="task-1",
        name="Build demo",
        mandatory=True,
        dependencies=(),
        effort_min_minutes=effort_minutes,
        effort_likely_minutes=effort_minutes,
        effort_max_minutes=effort_minutes,
        assumptions=("single-person estimate",),
    )
    availability = AvailabilityInput(
        horizon=PlanningHorizon(
            start=datetime(2026, 9, 27, 12, 0, tzinfo=UTC),
            end=datetime(2026, 9, 27, 15, 0, tzinfo=UTC),
        ),
        work_windows=(
            PlanningWorkWindow(
                start=datetime(2026, 9, 27, 12, 0, tzinfo=UTC),
                end=datetime(2026, 9, 27, 15, 0, tzinfo=UTC),
            ),
        ),
        preferences=PlanningPreferences(
            timezone="UTC",
            max_project_minutes_per_day=480,
            preferred_focus_minutes=60,
            buffer_target_minutes=0,
        ),
    )
    return PlanEvaluateRequestV1(
        report_bundle=_report_bundle(_ready_report()),
        readiness_context=ReadinessContextV1(
            user=ReadinessUserContextV1(),
            selected_scope="unscoped",
            require_technology_information=False,
        ),
        planning=PlanEvaluatePlanningV1(
            workload=WorkloadInput(tasks=(task,)),
            availability=availability,
        ),
    )


def _reevaluate_request() -> PlanReevaluateRequestV1:
    prior_basis = PriorEvaluationBasisSnapshotV1.model_validate(
        {
            "version": "evaluation-basis-v1",
            "domain_schema_version": "3.0.0",
            "fingerprint": "a" * 64,
            "report": {
                "competition_id": "cmp-entitlement-boundary",
                "report_version": 1,
                "reconciliation_policy_version": "reconciliation-v1",
                "assembly_policy_version": "canonical-v1",
                "assembly_material_fingerprint": "b" * 64,
            },
            "readiness": {
                "basis_version": "readiness-basis-v1",
                "basis_fingerprint": "c" * 64,
                "projection_version": "readiness-projection-v1",
                "rule_version": "1.0",
            },
            "planning": None,
        }
    )
    return PlanReevaluateRequestV1(
        prior=PriorEvaluationV1(
            evaluation_id=UUID("00000000-0000-4000-8000-000000000001"),
            basis=prior_basis,
        ),
        current=_plan_request(),
    )


def _source_metadata() -> SourceMetadataV1:
    return SourceMetadataV1(
        source_id="src-official",
        source_type=SourceType.OFFICIAL_RULES,
        authority_rank={"basis": "official_rules", "tier": 1},
        scope={"category": "all"},
        freshness_metadata={},
    )


def _assert_no_monetization_fields(model_type) -> None:
    names = {name.lower() for name in model_type.model_fields}
    assert names.isdisjoint(_MONETIZATION_NAMES)


@pytest.mark.parametrize(
    "model_type",
    [
        CompetitionAnalyzeUrlRequestV1,
        CompetitionAnalyzePdfMetadataV1,
        PlanEvaluateRequestV1,
        PlanReevaluateRequestV1,
        ReportBasisV1,
        ReadinessBasisV1,
        PlanningBasisV1,
        EvaluationBasisV1,
        ReadinessRequest,
        SolverConfig,
    ],
)
def test_correctness_contracts_expose_no_monetization_authority(model_type) -> None:
    _assert_no_monetization_fields(model_type)


@pytest.mark.parametrize(
    "callable_obj",
    [
        evaluate_readiness,
        reconcile_field,
        solve_candidate_allocations,
        assess_feasibility_run,
        build_recommendation,
    ],
)
def test_correctness_engines_accept_no_monetization_parameter(callable_obj) -> None:
    names = {name.lower() for name in inspect.signature(callable_obj).parameters}
    assert names.isdisjoint(_MONETIZATION_NAMES)


@pytest.mark.parametrize(
    "field_name",
    ["entitlement", "subscription_tier", "is_premium", "revenuecat_customer"],
)
def test_competition_url_api_rejects_monetization_channels(field_name: str) -> None:
    payload = CompetitionAnalyzeUrlRequestV1(
        competition_id="cmp-entitlement-boundary",
        url="https://example.test/rules",
        source=_source_metadata(),
    ).model_dump(mode="json")
    payload[field_name] = "premium"

    response = TestClient(app).post(
        "/api/v1/competitions/analyze/url",
        json=payload,
    )

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "VALIDATION_ERROR"


@pytest.mark.parametrize(
    "field_name",
    ["entitlement", "subscription_tier", "is_premium", "revenuecat_customer"],
)
def test_plan_evaluate_api_rejects_monetization_channels(field_name: str) -> None:
    payload = _plan_request().model_dump(mode="json", warnings=False)
    payload[field_name] = "premium"

    response = TestClient(app).post(
        "/api/v1/plans/evaluate",
        json=payload,
    )

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "VALIDATION_ERROR"


def test_plan_evaluate_rejects_nested_monetization_authority() -> None:
    payload = _plan_request().model_dump(mode="json", warnings=False)
    payload["readiness_context"]["is_premium"] = True

    response = TestClient(app).post(
        "/api/v1/plans/evaluate",
        json=payload,
    )

    assert response.status_code == 422
    body = response.json()
    assert body["error"]["code"] == "VALIDATION_ERROR"
    assert any(
        detail["path"] == "/readiness_context/is_premium"
        for detail in body["error"]["details"]
    )


def test_re_evaluate_api_rejects_monetization_authority_in_current_request() -> None:
    payload = _reevaluate_request().model_dump(mode="json", warnings=False)
    payload["current"]["planning"]["subscription_tier"] = "pro"

    response = TestClient(app).post(
        "/api/v1/plans/re-evaluate",
        json=payload,
    )

    assert response.status_code == 422
    body = response.json()
    assert body["error"]["code"] == "VALIDATION_ERROR"
    assert body["transition"] is None


def test_pdf_metadata_contract_rejects_entitlement_field() -> None:
    payload = CompetitionAnalyzePdfMetadataV1(
        competition_id="cmp-entitlement-boundary",
        document_id="doc-1",
        source=_source_metadata(),
    ).model_dump(mode="json")
    payload["entitlement"] = {"tier": "pro"}

    with pytest.raises(ValidationError) as captured:
        CompetitionAnalyzePdfMetadataV1.model_validate(payload)

    assert any(
        item["type"] == "extra_forbidden"
        and tuple(item["loc"]) == ("entitlement",)
        for item in captured.value.errors()
    )


def test_legacy_readiness_ignores_unknown_entitlement_instead_of_consulting_it() -> None:
    request = ReadinessRequest.model_validate(
        {
            "evaluated_at": "2026-10-01T00:00:00Z",
            "submission_deadline": "2026-09-30T23:45:00Z",
            "has_applicable_deadline_extension": False,
            "eligibility": {},
            "user": {},
            "unresolved_critical_fields": [],
            "mandatory_information_complete": True,
            "entitlement": {"tier": "pro"},
        }
    )

    assert not hasattr(request, "entitlement")
    assert evaluate_readiness(request).status is ReadinessStatus.DEADLINE_PASSED


def test_entitlement_cannot_override_failed_eligibility() -> None:
    request = ReadinessRequest.model_validate(
        {
            "evaluated_at": "2026-09-27T13:20:17Z",
            "submission_deadline": "2026-09-30T23:45:00Z",
            "eligibility": {
                "minimum_age": 21,
                "requires_student": False,
                "allowed_regions": ["global"],
            },
            "user": {"age": 18},
            "entitlement": {"tier": "pro"},
        }
    )

    result = evaluate_readiness(request)

    assert result.status is ReadinessStatus.ELIGIBILITY_BLOCKED
    assert result.blocking_reasons == ["minimum_age_not_met"]


def _source(source_id: str) -> SourceRecord:
    return SourceRecord(
        source_id=source_id,
        source_type=SourceType.OFFICIAL_RULES,
        url_or_document_id=f"https://example.test/{source_id}",
        retrieved_at=datetime(2026, 9, 27, 12, 0, tzinfo=UTC),
        content_hash=f"sha256:{source_id}",
        authority_rank={"basis": "official_rules", "tier": 1},
        scope={"category": "all"},
        freshness_metadata={
            "effective_at": "2026-09-01T00:00:00Z",
            "supersedes_source_ids": [],
        },
    )


def _candidate_report(source_id: str, normalized: int) -> CandidateExtractionReport:
    evidence_id = f"ev-{source_id}-team-size"
    evidence = EvidenceSpan(
        evidence_id=evidence_id,
        source_id=source_id,
        page_or_locator="page:1/team_size",
        raw_text_or_visual_reference=str(normalized),
        field_name="team_size",
        extraction_path=ExtractionPath.NATIVE,
        extractor_version="test-v1",
    )
    field = CandidateField(
        field_name="team_size",
        raw_value=normalized,
        normalized_value=normalized,
        evidence_ids=[evidence_id],
        extraction_path=ExtractionPath.NATIVE,
        confidence=0.9,
        scope={"category": "all"},
    )
    return CandidateExtractionReport(
        source_id=source_id,
        extraction_path=ExtractionPath.NATIVE,
        fields=[field],
        evidence=[evidence],
    )


def test_source_conflict_remains_conflict_without_monetization_authority() -> None:
    left = _source("src-left")
    right = _source("src-right")

    result = reconcile_field(
        "team_size",
        [
            _candidate_report("src-left", 2),
            _candidate_report("src-right", 4),
        ],
        [left, right],
    )

    assert result.canonical_field.state is CanonicalFieldState.CONFLICT
    assert result.canonical_field.value is None


def test_revenuecat_required_technology_is_competition_fact_not_entitlement() -> None:
    report = _ready_report(required_technologies=["RevenueCat"])
    request = build_readiness_request(
        canonical_report=report,
        user=UserContext(),
        selected_scope="unscoped",
        evaluated_at=datetime(2026, 9, 27, 13, 20, 17, tzinfo=UTC),
        require_technology_information=True,
    )

    result = evaluate_readiness(request)

    assert result.status is ReadinessStatus.READY_TO_EVALUATE
    assert "RevenueCat" in report.canonical_fields["required_technologies"].normalized_value


def test_solver_infeasible_remains_domain_result_without_tier_semantics() -> None:
    result = evaluate_plan(
        _plan_request(effort_minutes=200),
        clock=lambda: datetime(2026, 9, 27, 13, 20, 17, tzinfo=UTC),
        evaluation_id_factory=lambda: UUID(
            "00000000-0000-4000-8000-000000000002"
        ),
    )

    assert result.planning is not None
    assert (
        result.planning.feasibility
        is FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS
    )


def test_planning_policy_candidate_semantics_are_not_tier_dependent() -> None:
    parameters = dict(PLANNING_POLICY.material_parameters)

    assert _MAX_CANDIDATES == 3
    assert parameters["max_candidates"] == 3
    assert parameters["public_candidate_scenario"] == "LIKELY"
    assert set(parameters).isdisjoint(_MONETIZATION_NAMES)
