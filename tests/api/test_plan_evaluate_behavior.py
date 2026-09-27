"""Behavioral acceptance tests for Issue 4A product evaluation."""

from __future__ import annotations

import json
from datetime import UTC, datetime
from importlib.metadata import PackageNotFoundError
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

import apps.api.routes.plans as plans_route
import apps.api.services.plan_evaluation as plan_evaluation_service
import apps.api.services.reevaluation as reevaluation_service
from apps.api.canonical_json import jcs_sha256
from apps.api.contracts import (
    CanonicalReportBundleV1,
    CanonicalReportRefV1,
    PlanEvaluatePlanningV1,
    PlanEvaluateRequestV1,
    PlanReevaluateRequestV1,
    PriorEvaluationBasisSnapshotV1,
    PriorEvaluationV1,
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
from apps.api.services.reevaluation import (
    ReevaluationContextInvalid,
    ReevaluationExecutionFailure,
    reevaluate_plan,
)
import engine.feasibility.service as feasibility_service
from engine.feasibility.service import FeasibilityExecutionError
from engine.scheduler.models import SolverResult, SolverRunStatus
from packages.contracts import (
    AcceptedCommitment,
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


def test_readiness_fingerprint_stops_after_first_eligibility_blocker() -> None:
    report = _ready_report(
        deadline=datetime(2026, 9, 30, 23, 45, tzinfo=UTC)
    )
    fields = dict(report.canonical_fields)
    fields["eligibility"] = _candidate_field(
        "eligibility",
        value="21+ students in Indonesia",
        normalized={
            "minimum_age": 21,
            "requires_student": True,
            "allowed_regions": ["indonesia"],
        },
    )
    report = report.model_copy(update={"canonical_fields": fields})

    first_request = _request_for_report(
        report,
        user=ReadinessUserContextV1(
            age=18,
            student_status=True,
            country="Indonesia",
        ),
    )
    second_request = _request_for_report(
        report,
        user=ReadinessUserContextV1(
            age=18,
            student_status=False,
            country="Singapore",
        ),
    )

    first = evaluate_plan(
        first_request,
        clock=_clock,
        evaluation_id_factory=_id_one,
    )
    second = evaluate_plan(
        second_request,
        clock=_clock,
        evaluation_id_factory=_id_two,
    )

    assert first.readiness.status is ReadinessStatus.ELIGIBILITY_BLOCKED
    assert second.readiness.status is ReadinessStatus.ELIGIBILITY_BLOCKED
    assert first.readiness.blocking_reasons == ["minimum_age_not_met"]
    assert second.readiness.blocking_reasons == ["minimum_age_not_met"]
    assert (
        first.basis.readiness.basis_fingerprint
        == second.basis.readiness.basis_fingerprint
    )


def _route_with_fixed_clock(request: PlanEvaluateRequestV1):
    return plan_evaluation_service.evaluate_plan(
        request,
        clock=_clock,
        evaluation_id_factory=_id_one,
    )


def test_availability_execution_failure_has_availability_error_stage(
    monkeypatch,
) -> None:
    def fail_availability(_value):
        raise RuntimeError("private availability detail")

    monkeypatch.setattr(
        plan_evaluation_service,
        "build_availability",
        fail_availability,
    )
    monkeypatch.setattr(plans_route, "evaluate_plan", _route_with_fixed_clock)

    response = TestClient(app).post(
        "/api/v1/plans/evaluate",
        json=_request(effort_minutes=60).model_dump(mode="json"),
    )

    assert response.status_code == 500
    body = response.json()
    assert body["error"]["code"] == "AVAILABILITY_EXECUTION_FAILED"
    assert body["error"]["stage"] == "availability"
    assert "private availability detail" not in json.dumps(body)


def test_planning_runtime_metadata_failure_is_not_mislabeled_solver(
    monkeypatch,
) -> None:
    def missing_package(_name: str):
        raise PackageNotFoundError("ortools")

    monkeypatch.setattr(
        plan_evaluation_service,
        "package_version",
        missing_package,
    )
    monkeypatch.setattr(plans_route, "evaluate_plan", _route_with_fixed_clock)

    response = TestClient(app).post(
        "/api/v1/plans/evaluate",
        json=_request(effort_minutes=60).model_dump(mode="json"),
    )

    assert response.status_code == 500
    body = response.json()
    assert body["error"]["code"] == "PLANNING_RUNTIME_UNAVAILABLE"
    assert body["error"]["stage"] == "planning"


def test_solver_execution_failure_keeps_solver_error_stage(
    monkeypatch,
) -> None:
    def fail_solver(*_args, **_kwargs):
        raise FeasibilityExecutionError("private solver failure")

    monkeypatch.setattr(
        plan_evaluation_service,
        "assess_feasibility_run",
        fail_solver,
    )
    monkeypatch.setattr(plans_route, "evaluate_plan", _route_with_fixed_clock)

    response = TestClient(app).post(
        "/api/v1/plans/evaluate",
        json=_request(effort_minutes=60).model_dump(mode="json"),
    )

    assert response.status_code == 500
    body = response.json()
    assert body["error"]["code"] == "SOLVER_EXECUTION_FAILED"
    assert body["error"]["stage"] == "solver"


def test_server_produced_public_model_failure_normalizes_to_invariant_error(
    monkeypatch,
) -> None:
    def broken_planning_decision(**_kwargs):
        raise ValueError("private public-model invariant detail")

    monkeypatch.setattr(
        plan_evaluation_service,
        "PlanningDecisionV1",
        broken_planning_decision,
    )
    monkeypatch.setattr(plans_route, "evaluate_plan", _route_with_fixed_clock)

    response = TestClient(app).post(
        "/api/v1/plans/evaluate",
        json=_request(effort_minutes=60).model_dump(mode="json"),
    )

    assert response.status_code == 500
    body = response.json()
    assert body["error"]["code"] == "EVALUATION_INVARIANT_FAILED"
    assert body["error"]["stage"] == "evaluation"
    assert "private public-model invariant detail" not in json.dumps(body)


def _prior_request(
    *,
    prior: PlanEvaluateRequestV1 | None = None,
    current: PlanEvaluateRequestV1 | None = None,
) -> tuple[PlanReevaluateRequestV1, object]:
    base_request = prior or _request(effort_minutes=60)
    prior_result = evaluate_plan(
        base_request,
        clock=_clock,
        evaluation_id_factory=_id_one,
    )
    prior_basis = PriorEvaluationBasisSnapshotV1.model_validate(
        prior_result.basis.model_dump(mode="json", warnings=False)
    )
    request = PlanReevaluateRequestV1(
        prior=PriorEvaluationV1(
            evaluation_id=prior_result.evaluation_id,
            basis=prior_basis,
        ),
        current=current or base_request,
    )
    return request, prior_result


def test_reevaluate_same_basis_is_noop_without_solver_or_uuid(monkeypatch) -> None:
    request, prior_result = _prior_request()

    def forbidden_solver(*_args, **_kwargs):
        raise AssertionError("solver must not run for UNCHANGED")

    def forbidden_uuid():
        raise AssertionError("UUID must not be generated for UNCHANGED")

    monkeypatch.setattr(
        plan_evaluation_service,
        "assess_feasibility_run",
        forbidden_solver,
    )
    result = reevaluate_plan(
        request,
        clock=_clock,
        evaluation_id_factory=forbidden_uuid,
    )

    assert result.transition.kind == "UNCHANGED"
    assert result.transition.prior_evaluation_freshness == "CURRENT"
    assert result.transition.change_reasons == ()
    assert result.transition.current_basis_fingerprint == prior_result.basis.fingerprint
    assert result.evaluation is None


def test_material_schedule_change_supersedes_and_emits_fresh_evaluation() -> None:
    base = _request(effort_minutes=60)
    availability = base.planning.availability.model_copy(
        update={
            "work_windows": (
                PlanningWorkWindow(
                    start=datetime(2026, 9, 27, 12, 0, tzinfo=UTC),
                    end=datetime(2026, 9, 27, 14, 30, tzinfo=UTC),
                ),
            )
        }
    )
    current = base.model_copy(
        update={
            "planning": base.planning.model_copy(
                update={"availability": availability}
            )
        }
    )
    request, prior_result = _prior_request(current=current)

    result = reevaluate_plan(
        request,
        clock=_clock,
        evaluation_id_factory=_id_two,
    )

    assert result.transition.kind == "SUPERSEDED"
    assert result.transition.prior_evaluation_freshness == "STALE"
    assert result.transition.change_reasons == ("PLANNING_BASIS_CHANGED",)
    assert result.evaluation is not None
    assert result.evaluation.evaluation_id == _id_two()
    assert result.evaluation.evaluation_id != prior_result.evaluation_id
    assert (
        result.transition.current_basis_fingerprint
        == result.evaluation.basis.fingerprint
    )


def test_newer_report_version_establishes_stale_before_availability_failure(
    monkeypatch,
) -> None:
    base = _request(effort_minutes=60)
    newer_report = base.report_bundle.report.model_copy(
        update={"report_version": base.report_bundle.report.report_version + 1}
    )
    current = base.model_copy(update={"report_bundle": _bundle(newer_report)})
    request, _ = _prior_request(current=current)

    def fail_availability(_value):
        raise RuntimeError("availability exploded")

    monkeypatch.setattr(
        plan_evaluation_service,
        "build_availability",
        fail_availability,
    )

    with pytest.raises(ReevaluationExecutionFailure) as captured:
        reevaluate_plan(request, clock=_clock)

    failure = captured.value
    assert failure.transition is not None
    assert failure.transition.kind == "SUPERSEDED"
    assert failure.transition.prior_evaluation_freshness == "STALE"
    assert failure.transition.current_basis_fingerprint is None
    assert failure.transition.change_reasons == ("REPORT_BASIS_CHANGED",)


def test_same_context_availability_failure_has_no_stale_transition(
    monkeypatch,
) -> None:
    request, _ = _prior_request()

    def fail_availability(_value):
        raise RuntimeError("availability exploded")

    monkeypatch.setattr(
        plan_evaluation_service,
        "build_availability",
        fail_availability,
    )

    with pytest.raises(ReevaluationExecutionFailure) as captured:
        reevaluate_plan(request, clock=_clock)

    assert captured.value.transition is None


def test_report_lineage_regression_is_context_invalid() -> None:
    base = _request(effort_minutes=60)
    older_report = base.report_bundle.report.model_copy(
        update={"report_version": base.report_bundle.report.report_version - 1}
    )
    current = base.model_copy(update={"report_bundle": _bundle(older_report)})
    request, _ = _prior_request(current=current)

    with pytest.raises(ReevaluationContextInvalid):
        reevaluate_plan(request, clock=_clock)


def test_reevaluate_http_preserves_stale_transition_on_solver_unknown(
    monkeypatch,
) -> None:
    base = _request(effort_minutes=60)
    task = base.planning.workload.tasks[0].model_copy(
        update={
            "effort_min_minutes": 61,
            "effort_likely_minutes": 61,
            "effort_max_minutes": 61,
        }
    )
    current = base.model_copy(
        update={
            "planning": base.planning.model_copy(
                update={"workload": WorkloadInput(tasks=(task,))}
            )
        }
    )
    request, _ = _prior_request(current=current)

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

    real_reevaluate = reevaluate_plan

    def deterministic(value: PlanReevaluateRequestV1):
        return real_reevaluate(
            value,
            clock=_clock,
            evaluation_id_factory=_id_two,
        )

    monkeypatch.setattr(plans_route, "reevaluate_plan", deterministic)
    response = TestClient(app).post(
        "/api/v1/plans/re-evaluate",
        json=request.model_dump(mode="json", warnings=False),
    )

    assert response.status_code == 503
    body = response.json()
    assert body["error"]["code"] == "SOLVER_INDETERMINATE"
    assert body["transition"]["kind"] == "SUPERSEDED"
    assert body["transition"]["prior_evaluation_freshness"] == "STALE"
    assert body["transition"]["current_basis_fingerprint"] is not None


def test_unknown_structural_prior_version_is_specialized_422() -> None:
    request, _ = _prior_request()
    payload = request.model_dump(mode="json", warnings=False)
    payload["prior"]["basis"]["planning"]["basis_version"] = "planning-basis-v2"
    payload["prior"]["basis"]["planning"]["future_field"] = "v2-only"

    response = TestClient(app).post(
        "/api/v1/plans/re-evaluate",
        json=payload,
    )

    assert response.status_code == 422
    body = response.json()
    assert body["error"]["code"] == "UNSUPPORTED_REEVALUATION_CONTRACT"
    assert body["transition"] is None


def test_valid_shape_wrong_prior_digest_is_context_invalid_409() -> None:
    request, _ = _prior_request()
    payload = request.model_dump(mode="json", warnings=False)
    payload["prior"]["basis"]["fingerprint"] = "f" * 64

    response = TestClient(app).post(
        "/api/v1/plans/re-evaluate",
        json=payload,
    )

    assert response.status_code == 409
    body = response.json()
    assert body["error"]["code"] == "REEVALUATION_CONTEXT_INVALID"
    assert body["transition"] is None


def test_malformed_prior_digest_is_validation_error() -> None:
    request, _ = _prior_request()
    payload = request.model_dump(mode="json", warnings=False)
    payload["prior"]["basis"]["fingerprint"] = "not-a-sha"

    response = TestClient(app).post(
        "/api/v1/plans/re-evaluate",
        json=payload,
    )

    assert response.status_code == 422
    body = response.json()
    assert body["error"]["code"] == "VALIDATION_ERROR"
    assert body["transition"] is None


def test_reevaluation_uses_one_server_clock_sample() -> None:
    request, _ = _prior_request()
    calls = 0

    def counting_clock() -> datetime:
        nonlocal calls
        calls += 1
        return _clock()

    result = reevaluate_plan(request, clock=counting_clock)

    assert result.transition.kind == "UNCHANGED"
    assert calls == 1


def _rewrite_prior_basis(
    request: PlanReevaluateRequestV1,
    mutate,
) -> PlanReevaluateRequestV1:
    payload = request.model_dump(mode="json", warnings=False)
    basis = payload["prior"]["basis"]
    mutate(basis)
    basis["fingerprint"] = jcs_sha256(
        {
            "version": basis["version"],
            "domain_schema_version": basis["domain_schema_version"],
            "report": basis["report"],
            "readiness": basis["readiness"],
            "planning": basis["planning"],
        }
    )
    return PlanReevaluateRequestV1.model_validate(payload)


def test_old_behavior_policy_version_is_parseable_and_becomes_stale() -> None:
    request, _ = _prior_request()
    changed = _rewrite_prior_basis(
        request,
        lambda basis: basis["planning"].update(
            {"policy_version": "planning-policy-v0"}
        ),
    )

    result = reevaluate_plan(
        changed,
        clock=_clock,
        evaluation_id_factory=_id_two,
    )

    assert result.transition.kind == "SUPERSEDED"
    assert result.transition.change_reasons == ("PLANNING_BASIS_CHANGED",)


def test_prior_strings_are_not_stripped_before_fingerprint_verification() -> None:
    request, _ = _prior_request()
    changed = _rewrite_prior_basis(
        request,
        lambda basis: basis["report"].update(
            {"reconciliation_policy_version": " reconciliation-v1 "}
        ),
    )

    assert (
        changed.prior.basis.report.reconciliation_policy_version
        == " reconciliation-v1 "
    )
    result = reevaluate_plan(
        changed,
        clock=_clock,
        evaluation_id_factory=_id_two,
    )
    assert result.transition.kind == "SUPERSEDED"
    assert result.transition.change_reasons[0] == "REPORT_BASIS_CHANGED"


def test_static_planning_policy_witness_survives_availability_failure(
    monkeypatch,
) -> None:
    request, _ = _prior_request()
    changed = _rewrite_prior_basis(
        request,
        lambda basis: basis["planning"].update(
            {"policy_version": "planning-policy-v0"}
        ),
    )

    def fail_availability(_value):
        raise RuntimeError("availability failure")

    monkeypatch.setattr(
        plan_evaluation_service,
        "build_availability",
        fail_availability,
    )

    with pytest.raises(ReevaluationExecutionFailure) as captured:
        reevaluate_plan(changed, clock=_clock)

    transition = captured.value.transition
    assert transition is not None
    assert transition.change_reasons == ("PLANNING_BASIS_CHANGED",)
    assert transition.current_basis_fingerprint is None


def test_effective_planning_witness_survives_runtime_metadata_failure(
    monkeypatch,
) -> None:
    base = _request(effort_minutes=60)
    availability = base.planning.availability.model_copy(
        update={
            "work_windows": (
                PlanningWorkWindow(
                    start=datetime(2026, 9, 27, 12, 0, tzinfo=UTC),
                    end=datetime(2026, 9, 27, 14, 30, tzinfo=UTC),
                ),
            )
        }
    )
    current = base.model_copy(
        update={
            "planning": base.planning.model_copy(
                update={"availability": availability}
            )
        }
    )
    request, _ = _prior_request(current=current)

    def missing_package(_name: str):
        raise PackageNotFoundError("ortools")

    monkeypatch.setattr(
        plan_evaluation_service,
        "package_version",
        missing_package,
    )

    with pytest.raises(ReevaluationExecutionFailure) as captured:
        reevaluate_plan(request, clock=_clock)

    transition = captured.value.transition
    assert transition is not None
    assert transition.change_reasons == ("PLANNING_BASIS_CHANGED",)
    assert transition.current_basis_fingerprint is None


def test_solver_backend_version_only_change_is_planning_change() -> None:
    request, _ = _prior_request()
    changed = _rewrite_prior_basis(
        request,
        lambda basis: basis["planning"].update(
            {"solver_backend_version": "0.0-old"}
        ),
    )

    result = reevaluate_plan(
        changed,
        clock=_clock,
        evaluation_id_factory=_id_two,
    )

    assert result.transition.kind == "SUPERSEDED"
    assert result.transition.change_reasons == ("PLANNING_BASIS_CHANGED",)


def test_readiness_rule_version_invariant_preserves_existing_report_witness(
    monkeypatch,
) -> None:
    base = _request(effort_minutes=60)
    newer_report = base.report_bundle.report.model_copy(
        update={"report_version": base.report_bundle.report.report_version + 1}
    )
    current = base.model_copy(update={"report_bundle": _bundle(newer_report)})
    request, _ = _prior_request(current=current)

    real_readiness = plan_evaluation_service.evaluate_readiness

    def wrong_rule(value):
        result = real_readiness(value)
        return result.model_copy(update={"rule_version": "wrong-version"})

    monkeypatch.setattr(
        plan_evaluation_service,
        "evaluate_readiness",
        wrong_rule,
    )

    with pytest.raises(ReevaluationExecutionFailure) as captured:
        reevaluate_plan(request, clock=_clock)

    failure = captured.value
    assert failure.transition is not None
    assert failure.transition.change_reasons == ("REPORT_BASIS_CHANGED",)
    assert failure.cause.__class__.__name__ == "PlanEvaluationInvariantError"


def test_unknown_exception_after_witness_is_internal_error_with_stale_transition(
    monkeypatch,
) -> None:
    base = _request(effort_minutes=60)
    newer_report = base.report_bundle.report.model_copy(
        update={"report_version": base.report_bundle.report.report_version + 1}
    )
    current = base.model_copy(update={"report_bundle": _bundle(newer_report)})
    request, _ = _prior_request(current=current)

    def explode(_readiness):
        raise KeyError("private surprise")

    monkeypatch.setattr(
        reevaluation_service,
        "prepare_planning_material_stage",
        explode,
    )
    real_reevaluate = reevaluate_plan

    def deterministic(value: PlanReevaluateRequestV1):
        return real_reevaluate(value, clock=_clock)

    monkeypatch.setattr(plans_route, "reevaluate_plan", deterministic)
    response = TestClient(app).post(
        "/api/v1/plans/re-evaluate",
        json=request.model_dump(mode="json", warnings=False),
    )

    assert response.status_code == 500
    body = response.json()
    assert body["error"]["code"] == "INTERNAL_ERROR"
    assert body["transition"]["kind"] == "SUPERSEDED"
    assert "private surprise" not in json.dumps(body)


def test_unknown_exception_before_witness_is_internal_error_without_transition(
    monkeypatch,
) -> None:
    request, _ = _prior_request()

    def explode(_basis):
        raise RuntimeError("private early surprise")

    monkeypatch.setattr(
        reevaluation_service,
        "_verify_prior_fingerprint",
        explode,
    )
    real_reevaluate = reevaluate_plan

    def deterministic(value: PlanReevaluateRequestV1):
        return real_reevaluate(value, clock=_clock)

    monkeypatch.setattr(plans_route, "reevaluate_plan", deterministic)
    response = TestClient(app).post(
        "/api/v1/plans/re-evaluate",
        json=request.model_dump(mode="json", warnings=False),
    )

    assert response.status_code == 500
    body = response.json()
    assert body["error"]["code"] == "INTERNAL_ERROR"
    assert body["transition"] is None
    assert "private early surprise" not in json.dumps(body)


def test_accepted_commitment_id_only_change_is_semantically_unchanged() -> None:
    base = _request(effort_minutes=60)
    accepted_a = AcceptedCommitment(
        accepted_commitment_id="accepted-a",
        start_at=datetime(2026, 9, 27, 14, 0, tzinfo=UTC),
        end_at=datetime(2026, 9, 27, 14, 30, tzinfo=UTC),
        source="recommendation-a",
    )
    accepted_b = accepted_a.model_copy(
        update={
            "accepted_commitment_id": "accepted-b",
            "source": "recommendation-b",
        }
    )
    prior_availability = base.planning.availability.model_copy(
        update={"accepted_commitments": (accepted_a,)}
    )
    current_availability = base.planning.availability.model_copy(
        update={"accepted_commitments": (accepted_b,)}
    )
    prior_request = base.model_copy(
        update={
            "planning": base.planning.model_copy(
                update={"availability": prior_availability}
            )
        }
    )
    current_request = base.model_copy(
        update={
            "planning": base.planning.model_copy(
                update={"availability": current_availability}
            )
        }
    )
    request, _ = _prior_request(
        prior=prior_request,
        current=current_request,
    )

    result = reevaluate_plan(request, clock=_clock)

    assert result.transition.kind == "UNCHANGED"
    assert result.transition.change_reasons == ()
    assert result.evaluation is None


def test_context_invalid_after_tentative_report_witness_discards_transition(
    monkeypatch,
) -> None:
    base = _request(effort_minutes=60)
    newer_report = base.report_bundle.report.model_copy(
        update={"report_version": base.report_bundle.report.report_version + 1}
    )
    current = base.model_copy(update={"report_bundle": _bundle(newer_report)})
    request, _ = _prior_request(current=current)
    broken = _rewrite_prior_basis(
        request,
        lambda basis: basis.update({"planning": None}),
    )

    real_reevaluate = reevaluate_plan

    def deterministic(value: PlanReevaluateRequestV1):
        return real_reevaluate(value, clock=_clock)

    monkeypatch.setattr(plans_route, "reevaluate_plan", deterministic)
    response = TestClient(app).post(
        "/api/v1/plans/re-evaluate",
        json=broken.model_dump(mode="json", warnings=False),
    )

    assert response.status_code == 409
    body = response.json()
    assert body["error"]["code"] == "REEVALUATION_CONTEXT_INVALID"
    assert body["transition"] is None


def test_fingerprint_reason_contradiction_returns_invariant_with_null_transition(
    monkeypatch,
) -> None:
    request, _ = _prior_request()

    def fake_report_compare(_request, _current, witness):
        witness.add("REPORT_BASIS_CHANGED")

    monkeypatch.setattr(
        reevaluation_service,
        "_compare_report",
        fake_report_compare,
    )
    real_reevaluate = reevaluate_plan

    def deterministic(value: PlanReevaluateRequestV1):
        return real_reevaluate(value, clock=_clock)

    monkeypatch.setattr(plans_route, "reevaluate_plan", deterministic)
    response = TestClient(app).post(
        "/api/v1/plans/re-evaluate",
        json=request.model_dump(mode="json", warnings=False),
    )

    assert response.status_code == 500
    body = response.json()
    assert body["error"]["code"] == "EVALUATION_INVARIANT_FAILED"
    assert body["transition"] is None


def test_missing_structural_marker_is_validation_error() -> None:
    request, _ = _prior_request()
    payload = request.model_dump(mode="json", warnings=False)
    del payload["prior"]["basis"]["readiness"]["basis_version"]

    response = TestClient(app).post(
        "/api/v1/plans/re-evaluate",
        json=payload,
    )

    assert response.status_code == 422
    body = response.json()
    assert body["error"]["code"] == "VALIDATION_ERROR"
    assert body["transition"] is None
