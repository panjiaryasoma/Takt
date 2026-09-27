"""Behavioral acceptance tests for Issue 4A product evaluation."""

from __future__ import annotations

import json
from datetime import UTC, datetime
from uuid import UUID

from fastapi.testclient import TestClient

import apps.api.routes.plans as plans_route
import engine.feasibility.service as feasibility_service
from apps.api.contracts import (
    CanonicalReportBundleV1,
    CanonicalReportRefV1,
    PlanEvaluatePlanningV1,
    PlanEvaluateRequestV1,
    ReadinessContextV1,
    ReadinessUserContextV1,
)
from apps.api.fingerprints import report_wire_fingerprint
from apps.api.main import app
from apps.api.services.plan_evaluation import (
    PlanEvaluationIndeterminateError,
    evaluate_plan,
    planning_cutoff,
    verify_report_bundle,
)
from packages.contracts import (
    AvailabilityInput,
    CandidateField,
    CanonicalCompetitionReport,
    CanonicalField,
    CanonicalFieldState,
    ExtractionPath,
    FeasibilityStatus,
    PlanningHorizon,
    PlanningPreferences,
    PlanningWorkWindow,
    ReadinessStatus,
    RecommendationAction,
    Task,
    WorkloadInput,
)
from engine.scheduler.models import SolverResult, SolverRunStatus
from packages.contracts.source import CORE_CANONICAL_FIELDS


def _candidate_field(
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


def _ready_report(*, deadline: datetime) -> CanonicalCompetitionReport:
    fields = {
        name: CanonicalField(field_name=name, state=CanonicalFieldState.MISSING)
        for name in CORE_CANONICAL_FIELDS
    }
    fields["submission_deadline"] = _candidate_field(
        "submission_deadline",
        value="September 30, 2026 at 23:45 UTC",
        normalized=deadline,
    )
    fields["eligibility"] = _candidate_field(
        "eligibility",
        value="Open to everyone",
        normalized={
            "minimum_age": None,
            "requires_student": False,
            "allowed_regions": ["global"],
        },
    )
    fields["deliverables"] = _candidate_field(
        "deliverables",
        value=["demo"],
        normalized=["demo"],
    )
    return CanonicalCompetitionReport(
        competition_id="cmp-ready",
        report_version=4,
        source_ids=["src-ready"],
        canonical_fields=fields,
        unresolved_critical_fields=[],
    )


def _bundle(report: CanonicalCompetitionReport) -> CanonicalReportBundleV1:
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


def _request(*, effort_minutes: int) -> PlanEvaluateRequestV1:
    report = _ready_report(
        deadline=datetime(2026, 9, 30, 23, 45, tzinfo=UTC),
    )
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
        report_bundle=_bundle(report),
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


def _clock() -> datetime:
    return datetime(2026, 9, 27, 13, 20, 17, tzinfo=UTC)


def _id_one() -> UUID:
    return UUID("00000000-0000-4000-8000-000000000001")


def _id_two() -> UUID:
    return UUID("00000000-0000-4000-8000-000000000002")


def test_server_cutoff_clips_partial_window_and_candidates_never_start_before_it() -> None:
    result = evaluate_plan(
        _request(effort_minutes=60),
        clock=_clock,
        evaluation_id_factory=_id_one,
    )

    assert result.readiness.status is ReadinessStatus.READY_TO_EVALUATE
    assert result.planning is not None
    assert result.planning.recommendation is not None
    cutoff = planning_cutoff(_clock())
    assert cutoff == datetime(2026, 9, 27, 13, 21, tzinfo=UTC)

    windows = result.planning.recommendation.recommendation.suggested_windows
    assert windows
    assert all(item.start.astimezone(UTC) >= cutoff for item in windows)


def test_solver_infeasible_is_successful_domain_result_with_evaluation_id() -> None:
    result = evaluate_plan(
        _request(effort_minutes=200),
        clock=_clock,
        evaluation_id_factory=_id_one,
    )

    assert result.evaluation_id == _id_one()
    assert result.readiness.status is ReadinessStatus.READY_TO_EVALUATE
    assert result.planning is not None
    assert (
        result.planning.feasibility
        is FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS
    )
    assert result.planning.recommendation is None


def test_identical_semantic_inputs_are_deterministic_except_execution_identity() -> None:
    request = _request(effort_minutes=60)
    first = evaluate_plan(
        request,
        clock=_clock,
        evaluation_id_factory=_id_one,
    )
    second = evaluate_plan(
        request,
        clock=_clock,
        evaluation_id_factory=_id_two,
    )

    assert first.evaluation_id != second.evaluation_id
    assert first.basis == second.basis
    assert first.readiness == second.readiness
    assert first.planning is not None and second.planning is not None
    assert first.planning.feasibility == second.planning.feasibility

    first_set = first.planning.recommendation
    second_set = second.planning.recommendation
    assert first_set is not None and second_set is not None
    assert (
        first_set.primary_candidate.candidate_id
        == second_set.primary_candidate.candidate_id
    )
    assert first_set.recommendation == second_set.recommendation
    assert (
        first_set.recommendation.recommended_candidate_id
        == first_set.primary_candidate.candidate_id
    )
    assert tuple(
        item.candidate_id for item in first_set.recommendation.alternatives
    ) == tuple(
        item.candidate_id for item in first_set.alternative_candidates
    )
    assert first.basis.report.competition_id == request.report_bundle.ref.competition_id
    assert first.basis.report.report_version == request.report_bundle.ref.report_version


def test_aware_datetime_inside_any_survives_report_wire_round_trip() -> None:
    bundle = _bundle(
        _ready_report(
            deadline=datetime(2026, 9, 30, 23, 45, tzinfo=UTC),
        )
    )
    raw = json.loads(json.dumps(bundle.model_dump(mode="json")))
    round_tripped = CanonicalReportBundleV1.model_validate(raw)

    verify_report_bundle(round_tripped)
    assert (
        round_tripped.ref.wire_fingerprint
        == bundle.ref.wire_fingerprint
    )


def test_infeasible_http_response_is_200_not_generic_error(monkeypatch) -> None:
    real_evaluate = evaluate_plan

    def deterministic(request: PlanEvaluateRequestV1):
        return real_evaluate(
            request,
            clock=_clock,
            evaluation_id_factory=_id_one,
        )

    monkeypatch.setattr(plans_route, "evaluate_plan", deterministic)
    response = TestClient(app).post(
        "/api/v1/plans/evaluate",
        json=_request(effort_minutes=200).model_dump(mode="json"),
    )

    assert response.status_code == 200
    body = response.json()
    assert (
        body["planning"]["feasibility"]
        == "NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS"
    )
    assert body["planning"]["recommendation"] is None
    assert body["evaluation_id"] == str(_id_one())


def test_solver_unknown_maps_to_503_without_internal_message(monkeypatch) -> None:
    def indeterminate(request: PlanEvaluateRequestV1):
        del request
        raise PlanEvaluationIndeterminateError("secret solver internals")

    monkeypatch.setattr(plans_route, "evaluate_plan", indeterminate)
    response = TestClient(app).post(
        "/api/v1/plans/evaluate",
        json=_request(effort_minutes=60).model_dump(mode="json"),
    )

    assert response.status_code == 503
    body = response.json()
    assert body["error"]["code"] == "SOLVER_INDETERMINATE"
    assert "secret solver internals" not in json.dumps(body)


def test_public_response_does_not_leak_internal_feasibility_artifacts() -> None:
    result = evaluate_plan(
        _request(effort_minutes=60),
        clock=_clock,
        evaluation_id_factory=_id_one,
    )
    payload = json.dumps(result.model_dump(mode="json"))

    for internal_name in (
        "scenario_results",
        "likely_solver_result",
        "baseline_workload_analysis",
        "recommendation_payload",
        "source_feasibility_status",
    ):
        assert internal_name not in payload


def test_readiness_fingerprint_ignores_clock_changes_with_same_open_decision() -> None:
    request = _request(effort_minutes=60)
    morning = lambda: datetime(2026, 9, 27, 10, 0, tzinfo=UTC)
    later = lambda: datetime(2026, 9, 27, 11, 0, tzinfo=UTC)

    first = evaluate_plan(
        request,
        clock=morning,
        evaluation_id_factory=_id_one,
    )
    second = evaluate_plan(
        request,
        clock=later,
        evaluation_id_factory=_id_two,
    )

    assert first.readiness.status is ReadinessStatus.READY_TO_EVALUATE
    assert second.readiness.status is ReadinessStatus.READY_TO_EVALUATE
    assert (
        first.basis.readiness.basis_fingerprint
        == second.basis.readiness.basis_fingerprint
    )


def test_server_clock_after_deadline_blocks_before_planning() -> None:
    after_deadline = lambda: datetime(2026, 10, 1, 0, 0, tzinfo=UTC)

    result = evaluate_plan(
        _request(effort_minutes=60),
        clock=after_deadline,
        evaluation_id_factory=_id_one,
    )

    assert result.evaluation_id == _id_one()
    assert result.evaluated_at == after_deadline()
    assert result.readiness.status is ReadinessStatus.DEADLINE_PASSED
    assert result.planning is None
    assert result.basis.planning is None


def _review_report(*, deadline: datetime) -> CanonicalCompetitionReport:
    report = _ready_report(deadline=deadline)
    left = CandidateField(
        field_name="deliverables",
        raw_value=["demo"],
        normalized_value=["demo"],
        evidence_ids=["ev-deliverables-a"],
        extraction_path=ExtractionPath.NATIVE,
        confidence=None,
        scope={},
    )
    right = CandidateField(
        field_name="deliverables",
        raw_value=["pitch"],
        normalized_value=["pitch"],
        evidence_ids=["ev-deliverables-b"],
        extraction_path=ExtractionPath.NATIVE,
        confidence=None,
        scope={},
    )
    fields = dict(report.canonical_fields)
    fields["deliverables"] = CanonicalField(
        field_name="deliverables",
        state=CanonicalFieldState.CONFLICT,
        candidates=[left, right],
        evidence_ids=["ev-deliverables-a", "ev-deliverables-b"],
    )
    return report.model_copy(update={"canonical_fields": fields})


def _request_for_report(
    report: CanonicalCompetitionReport,
    *,
    user: ReadinessUserContextV1 | None = None,
) -> PlanEvaluateRequestV1:
    base = _request(effort_minutes=60)
    return base.model_copy(
        update={
            "report_bundle": _bundle(report),
            "readiness_context": ReadinessContextV1(
                user=user or ReadinessUserContextV1(),
                selected_scope="unscoped",
                require_technology_information=False,
            ),
        }
    )


def test_readiness_fingerprint_is_stage_aware_for_early_review_stop() -> None:
    report = _review_report(
        deadline=datetime(2026, 9, 30, 23, 45, tzinfo=UTC)
    )
    first_request = _request_for_report(
        report,
        user=ReadinessUserContextV1(
            age=20,
            student_status=True,
            country="Indonesia",
        ),
    )
    second_request = _request_for_report(
        report,
        user=ReadinessUserContextV1(
            age=99,
            student_status=False,
            country="Singapore",
        ),
    )

    first = evaluate_plan(
        first_request,
        clock=lambda: datetime(2026, 9, 29, 12, 0, tzinfo=UTC),
        evaluation_id_factory=_id_one,
    )
    second = evaluate_plan(
        second_request,
        clock=lambda: datetime(2026, 10, 1, 12, 0, tzinfo=UTC),
        evaluation_id_factory=_id_two,
    )

    assert first.readiness.status is ReadinessStatus.NEEDS_REVIEW
    assert second.readiness.status is ReadinessStatus.NEEDS_REVIEW
    assert first.basis.planning is None
    assert second.basis.planning is None
    assert (
        first.basis.readiness.basis_fingerprint
        == second.basis.readiness.basis_fingerprint
    )


def test_public_candidate_pool_actions_and_trace_are_resolvable() -> None:
    result = evaluate_plan(
        _request(effort_minutes=60),
        clock=_clock,
        evaluation_id_factory=_id_one,
    )

    assert result.planning is not None
    planning = result.planning
    assert planning.candidates
    assert planning.recommendation is not None

    candidate_ids = tuple(item.ref.candidate_id for item in planning.candidates)
    recommendation = planning.recommendation
    referenced_ids = (
        recommendation.primary_candidate.candidate_id,
        *(
            item.candidate_id
            for item in recommendation.alternative_candidates
        ),
    )
    assert referenced_ids == candidate_ids
    assert all(
        item.ref.evaluation_id == result.evaluation_id
        for item in planning.candidates
    )
    assert planning.allowed_actions[-2:] == (
        RecommendationAction.EDIT_CONSTRAINTS,
        RecommendationAction.IGNORE,
    )

    trace = recommendation.trace
    assert trace.competition_id == result.basis.report.competition_id
    assert trace.report_version == result.basis.report.report_version
    assert (
        trace.assembly_material_fingerprint
        == result.basis.report.assembly_material_fingerprint
    )
    assert trace.evaluation_basis_fingerprint == result.basis.fingerprint
    assert result.basis.planning is not None
    assert (
        trace.planning_basis_fingerprint
        == result.basis.planning.basis_fingerprint
    )
    assert trace.planning_policy_version == result.basis.planning.policy_version


def test_infeasible_public_decision_preserves_advisory_actions() -> None:
    result = evaluate_plan(
        _request(effort_minutes=200),
        clock=_clock,
        evaluation_id_factory=_id_one,
    )

    assert result.planning is not None
    assert result.planning.candidates == ()
    assert result.planning.recommendation is None
    assert result.planning.allowed_actions == (
        RecommendationAction.EDIT_CONSTRAINTS,
        RecommendationAction.IGNORE,
    )


def test_real_solver_unknown_pipeline_maps_to_503(monkeypatch) -> None:
    def unknown_solver(*_args, **_kwargs):
        return SolverResult(
            status=SolverRunStatus.UNKNOWN,
            candidate_allocations=(),
            reason_codes=("CP_SAT_UNKNOWN",),
        )

    monkeypatch.setattr(
        feasibility_service,
        "solve_candidate_allocations",
        unknown_solver,
    )
    real_evaluate = evaluate_plan

    def deterministic(request: PlanEvaluateRequestV1):
        return real_evaluate(
            request,
            clock=_clock,
            evaluation_id_factory=_id_one,
        )

    monkeypatch.setattr(plans_route, "evaluate_plan", deterministic)
    response = TestClient(app).post(
        "/api/v1/plans/evaluate",
        json=_request(effort_minutes=60).model_dump(mode="json"),
    )

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "SOLVER_INDETERMINATE"
