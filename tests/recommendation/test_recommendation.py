from __future__ import annotations

from datetime import UTC, date, datetime, timedelta

import pytest

import engine.feasibility.service as feasibility_service
from engine.availability.models import AvailabilityResult, DailyCapacity
from engine.feasibility import assess_feasibility_run
from engine.feasibility.models import (
    FeasibilityAssessment,
    FeasibilityRun,
    FeasibilityScenario,
    FeasibilityScenarioResult,
)
from engine.recommendation import (
    RecommendationBuildInput,
    RecommendationEvidenceError,
    RecommendationInputError,
    RecommendationInvariantError,
    RecommendationTraceContext,
    build_recommendation,
    materialize_public_recommendation,
)
from engine.scheduler.models import SolverConfig, SolverResult, SolverRunStatus
from engine.workload import analyze_workload
from packages.contracts import (
    AllocationBlock,
    AvailabilityBlock,
    AvailabilityType,
    CandidateAllocation,
    Task,
)
from packages.contracts.enums import FeasibilityStatus, RecommendationAction
from packages.contracts.workload import WorkloadAssumption, WorkloadInput

START = datetime(2026, 10, 1, 9, 0, tzinfo=UTC)


def _workload_input(
    *,
    assumptions: tuple[WorkloadAssumption, ...] = (),
) -> WorkloadInput:
    return WorkloadInput(
        tasks=(
            Task(
                task_id="core",
                name="Core deliverable",
                mandatory=True,
                dependencies=(),
                effort_min_minutes=60,
                effort_likely_minutes=120,
                effort_max_minutes=180,
                assumptions=(),
            ),
            Task(
                task_id="optional",
                name="Optional polish",
                mandatory=False,
                dependencies=(),
                effort_min_minutes=30,
                effort_likely_minutes=120,
                effort_max_minutes=120,
                assumptions=(),
            ),
        ),
        assumptions=assumptions,
    )


def _block(
    task_id: str = "core",
    *,
    start_offset: int = 0,
    minutes: int = 60,
) -> AllocationBlock:
    start = START + timedelta(minutes=start_offset)
    return AllocationBlock(
        task_id=task_id,
        start=start,
        end=start + timedelta(minutes=minutes),
        allocated_minutes=minutes,
        availability_source="window-1",
    )


def _candidate(
    *,
    candidate_id: str = "candidate-001",
    buffer_minutes: int = 60,
    work_blocks: tuple[AllocationBlock, ...] | None = None,
    violations: tuple[str, ...] = (),
) -> CandidateAllocation:
    if work_blocks is None:
        work_blocks = (_block(),)
    return CandidateAllocation(
        candidate_id=candidate_id,
        work_blocks=work_blocks,
        buffer_minutes=buffer_minutes,
        hard_constraint_violations=violations,
        assumptions=(),
    )


def _scenario_result(
    scenario: FeasibilityScenario,
    status: SolverRunStatus,
    *,
    buffer_minutes: int = 60,
    reason_codes: tuple[str, ...] = (),
) -> FeasibilityScenarioResult:
    feasible = status in {SolverRunStatus.OPTIMAL, SolverRunStatus.FEASIBLE}
    return FeasibilityScenarioResult(
        scenario=scenario,
        solver_status=status,
        candidate_id="candidate-001" if feasible else None,
        buffer_minutes=buffer_minutes if feasible else None,
        solver_reason_codes=reason_codes,
    )


def _run(
    status: FeasibilityStatus = FeasibilityStatus.FEASIBLE,
    *,
    candidate: CandidateAllocation | None = None,
    solver_status: SolverRunStatus = SolverRunStatus.OPTIMAL,
    solver_reason_codes: tuple[str, ...] = (),
    assessment_assumptions: tuple[WorkloadAssumption, ...] = (),
    baseline_assumptions: tuple[WorkloadAssumption, ...] | None = None,
) -> FeasibilityRun:
    if baseline_assumptions is None:
        baseline_assumptions = assessment_assumptions
    baseline = analyze_workload(
        _workload_input(assumptions=baseline_assumptions)
    )

    if status is FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS:
        likely_status = SolverRunStatus.INFEASIBLE
        likely_reason_codes = solver_reason_codes or ("LIKELY_NO_CAPACITY",)
        results = (
            _scenario_result(FeasibilityScenario.MIN, SolverRunStatus.OPTIMAL),
            _scenario_result(
                FeasibilityScenario.LIKELY,
                likely_status,
                reason_codes=likely_reason_codes,
            ),
            _scenario_result(FeasibilityScenario.MAX, SolverRunStatus.UNKNOWN),
            _scenario_result(
                FeasibilityScenario.FULL_SCOPE_LIKELY,
                SolverRunStatus.UNKNOWN,
            ),
        )
        assessment = FeasibilityAssessment(
            status=status,
            likely_candidate_id=None,
            scenario_results=results,
            reason_codes=("REQUIRED_LIKELY_INFEASIBLE",),
            sensitivity_codes=(
                "MINIMUM_EFFORT_SCENARIO_FEASIBLE",
                "LIKELY_EFFORT_SCENARIO_INFEASIBLE",
                "MAX_SCENARIO_UNKNOWN",
            ),
            assumptions=assessment_assumptions,
        )
        solver = SolverResult(
            status=SolverRunStatus.INFEASIBLE,
            candidate_allocations=(),
            reason_codes=likely_reason_codes,
        )
        return FeasibilityRun(
            assessment=assessment,
            likely_solver_result=solver,
            baseline_workload_analysis=baseline,
        )

    if candidate is None:
        candidate = _candidate()

    likely = _scenario_result(
        FeasibilityScenario.LIKELY,
        solver_status,
        buffer_minutes=candidate.buffer_minutes,
        reason_codes=solver_reason_codes,
    )
    if status is FeasibilityStatus.TIGHT_CAPACITY:
        maximum = _scenario_result(
            FeasibilityScenario.MAX,
            SolverRunStatus.INFEASIBLE,
        )
        full = _scenario_result(
            FeasibilityScenario.FULL_SCOPE_LIKELY,
            SolverRunStatus.INFEASIBLE,
        )
        reason_codes = (
            "REQUIRED_MAX_INFEASIBLE",
            "FULL_SCOPE_LIKELY_INFEASIBLE",
        )
        tradeoff_codes = ("OPTIONAL_SCOPE_DOES_NOT_FIT",)
        sensitivity_codes = (
            "MINIMUM_EFFORT_SCENARIO_FEASIBLE",
            "EFFORT_OVERRUN_BREAKS_PLAN",
        )
    elif status is FeasibilityStatus.FEASIBLE_WITH_TRADEOFFS:
        maximum = _scenario_result(FeasibilityScenario.MAX, SolverRunStatus.OPTIMAL)
        full = _scenario_result(
            FeasibilityScenario.FULL_SCOPE_LIKELY,
            SolverRunStatus.INFEASIBLE,
        )
        reason_codes = ("FULL_SCOPE_LIKELY_INFEASIBLE",)
        tradeoff_codes = ("OPTIONAL_SCOPE_DOES_NOT_FIT",)
        sensitivity_codes = (
            "MINIMUM_EFFORT_SCENARIO_FEASIBLE",
            "MAX_EFFORT_SCENARIO_FEASIBLE",
        )
    else:
        maximum = _scenario_result(FeasibilityScenario.MAX, SolverRunStatus.OPTIMAL)
        full = _scenario_result(
            FeasibilityScenario.FULL_SCOPE_LIKELY,
            SolverRunStatus.OPTIMAL,
        )
        reason_codes = (
            "ALL_REQUIRED_SCENARIOS_FEASIBLE",
            "FULL_SCOPE_LIKELY_FEASIBLE",
        )
        tradeoff_codes = ()
        sensitivity_codes = (
            "MINIMUM_EFFORT_SCENARIO_FEASIBLE",
            "MAX_EFFORT_SCENARIO_FEASIBLE",
        )

    assessment = FeasibilityAssessment(
        status=status,
        likely_candidate_id="candidate-001",
        scenario_results=(
            _scenario_result(FeasibilityScenario.MIN, SolverRunStatus.OPTIMAL),
            likely,
            maximum,
            full,
        ),
        reason_codes=reason_codes,
        tradeoff_codes=tradeoff_codes,
        sensitivity_codes=sensitivity_codes,
        assumptions=assessment_assumptions,
    )
    solver = SolverResult(
        status=solver_status,
        candidate_allocations=(candidate,),
        reason_codes=solver_reason_codes,
    )
    return FeasibilityRun(
        assessment=assessment,
        likely_solver_result=solver,
        baseline_workload_analysis=baseline,
    )


def _build(run: FeasibilityRun):
    return build_recommendation(
        RecommendationBuildInput(
            feasibility_run=run,
            trace_context=RecommendationTraceContext(
                competition_id="cmp-001",
                report_version=3,
            ),
        )
    )


# REC-001
def test_feasible_run_builds_primary_recommendation() -> None:
    assembly = _build(_run())
    assert assembly.recommendation_payload is not None
    assert assembly.primary_candidate_id == "candidate-001"
    assert assembly.source_feasibility_status is FeasibilityStatus.FEASIBLE


# REC-002
def test_tight_capacity_keeps_recommendation_and_sensitivity_rationale() -> None:
    assembly = _build(_run(FeasibilityStatus.TIGHT_CAPACITY))
    assert assembly.recommendation_payload is not None
    assert (
        "The current plan is sensitive to effort overruns."
        in assembly.recommendation_payload.rationale
    )


# REC-003
def test_tradeoff_status_exposes_tradeoff_prose() -> None:
    assembly = _build(_run(FeasibilityStatus.FEASIBLE_WITH_TRADEOFFS))
    assert assembly.recommendation_payload is not None
    assert assembly.recommendation_payload.tradeoffs == (
        "Some optional tasks would need to be dropped under the current constraints.",
    )


# REC-004
def test_not_feasible_returns_no_recommendation() -> None:
    assembly = _build(_run(FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS))
    assert assembly.recommendation_payload is None
    assert assembly.primary_candidate_id is None
    assert assembly.alternative_candidate_ids == ()


# REC-005
def test_primary_candidate_with_hard_violation_is_rejected() -> None:
    with pytest.raises(RecommendationInvariantError, match="hard-constraint"):
        _build(_run(candidate=_candidate(violations=("BROKEN",))))


# REC-006
def test_candidate_id_mismatch_is_rejected() -> None:
    with pytest.raises(RecommendationInvariantError, match="candidate ID"):
        _build(_run(candidate=_candidate(candidate_id="candidate-999")))


# REC-007, REC-008
def test_next_work_and_windows_are_literal_chronological_projection() -> None:
    later = _block(start_offset=120, minutes=30)
    earlier = _block(start_offset=30, minutes=60)
    assembly = _build(_run(candidate=_candidate(work_blocks=(later, earlier))))
    payload = assembly.recommendation_payload
    assert payload is not None
    assert [item.start for item in payload.suggested_windows] == [
        earlier.start,
        later.start,
    ]
    assert payload.recommended_next_work is not None
    assert payload.recommended_next_work.task_id == "core"
    assert payload.recommended_next_work.task_name == "Core deliverable"
    assert payload.recommended_next_work.start == earlier.start


# REC-009
def test_assumptions_are_preserved_from_assessment() -> None:
    assumption = WorkloadAssumption(description="scope remains unchanged")
    payload = _build(
        _run(
            assessment_assumptions=(assumption,),
            baseline_assumptions=(assumption,),
        )
    ).recommendation_payload
    assert payload is not None
    assert payload.assumptions == (assumption,)


# REC-011
def test_unknown_assessment_evidence_is_rejected() -> None:
    run = _run()
    broken_assessment = run.assessment.model_copy(
        update={"reason_codes": ("UNKNOWN_REASON",)}
    )
    broken = run.model_copy(update={"assessment": broken_assessment})
    with pytest.raises(RecommendationEvidenceError):
        _build(broken)


# REC-012, REC-013 deferred
def test_mvp_has_no_fake_alternatives_or_choose_alternative_action() -> None:
    assembly = _build(_run())
    assert assembly.alternative_candidate_ids == ()
    assert assembly.recommendation_payload is not None
    assert assembly.recommendation_payload.alternatives == ()
    assert RecommendationAction.CHOOSE_ALTERNATIVE not in assembly.allowed_actions


# REC-014
def test_same_semantic_input_produces_same_assembly() -> None:
    first = _build(_run())
    second = _build(_run())
    assert first == second


# REC-015, REC-016, REC-017
def test_build_does_not_mutate_same_run_inputs() -> None:
    run = _run()
    before = run.model_dump(mode="python")
    _build(run)
    assert run.model_dump(mode="python") == before


# REC-018, REC-019, REC-020
def test_allowed_actions_are_advisory_metadata_only() -> None:
    assembly = _build(_run())
    assert assembly.allowed_actions == (
        RecommendationAction.ACCEPT,
        RecommendationAction.EDIT_CONSTRAINTS,
        RecommendationAction.IGNORE,
    )


# REC-021
def test_zero_work_candidate_is_valid_with_no_next_work_or_windows() -> None:
    assembly = _build(_run(candidate=_candidate(work_blocks=())))
    payload = assembly.recommendation_payload
    assert payload is not None
    assert payload.recommended_next_work is None
    assert payload.suggested_windows == ()


# REC-022, REC-036
def test_unknown_candidate_task_reference_is_rejected() -> None:
    candidate = _candidate(work_blocks=(_block(task_id="ghost"),))
    with pytest.raises(RecommendationInvariantError, match="unknown workload task IDs"):
        _build(_run(candidate=candidate))


# REC-023
def test_not_feasible_run_rejects_stale_solver_candidate() -> None:
    run = _run(FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS)
    stale_solver = SolverResult(
        status=SolverRunStatus.OPTIMAL,
        candidate_allocations=(_candidate(),),
        reason_codes=(),
    )
    broken = run.model_copy(update={"likely_solver_result": stale_solver})
    with pytest.raises(RecommendationInvariantError):
        _build(broken)


# REC-024
def test_not_feasible_actions_are_canonical_and_conditional() -> None:
    assembly = _build(_run(FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS))
    assert assembly.allowed_actions == (
        RecommendationAction.EDIT_CONSTRAINTS,
        RecommendationAction.IGNORE,
    )


# REC-025
def test_likely_solver_status_mismatch_is_rejected() -> None:
    run = _run()
    altered_solver = run.likely_solver_result.model_copy(
        update={"status": SolverRunStatus.FEASIBLE}
    )
    broken = run.model_copy(update={"likely_solver_result": altered_solver})
    with pytest.raises(RecommendationInvariantError, match="solver status"):
        _build(broken)


# REC-026 + Issue #3 multi-candidate completion
def test_multiple_valid_candidates_are_ranked_and_exposed_as_alternatives() -> None:
    run = _run()
    primary = run.likely_solver_result.candidate_allocations[0]
    extra = _candidate(
        candidate_id="candidate-002",
        work_blocks=(_block(start_offset=30),),
    )
    altered_solver = run.likely_solver_result.model_copy(
        update={"candidate_allocations": (extra, primary)}
    )
    expanded = run.model_copy(update={"likely_solver_result": altered_solver})

    assembly = _build(expanded)

    assert assembly.primary_candidate_id == "candidate-001"
    assert assembly.alternative_candidate_ids == ("candidate-002",)
    assert assembly.recommendation_payload is not None
    assert tuple(
        item.candidate_id
        for item in assembly.recommendation_payload.alternatives
    ) == ("candidate-002",)
    assert RecommendationAction.CHOOSE_ALTERNATIVE in assembly.allowed_actions


def test_invalid_candidate_is_excluded_from_ranking_and_alternatives() -> None:
    run = _run()
    primary = run.likely_solver_result.candidate_allocations[0]
    invalid = _candidate(
        candidate_id="candidate-broken",
        violations=("BROKEN",),
    )
    altered_solver = run.likely_solver_result.model_copy(
        update={"candidate_allocations": (invalid, primary)}
    )
    expanded = run.model_copy(update={"likely_solver_result": altered_solver})

    assembly = _build(expanded)

    assert assembly.primary_candidate_id == "candidate-001"
    assert assembly.alternative_candidate_ids == ()
    assert RecommendationAction.CHOOSE_ALTERNATIVE not in assembly.allowed_actions


# REC-027
def test_candidate_buffer_mismatch_is_rejected() -> None:
    run = _run(candidate=_candidate(buffer_minutes=90))
    broken_likely = run.assessment.scenario_results[1].model_copy(
        update={"buffer_minutes": 60}
    )
    results = list(run.assessment.scenario_results)
    results[1] = broken_likely
    broken_assessment = run.assessment.model_copy(
        update={"scenario_results": tuple(results)}
    )
    broken = run.model_copy(update={"assessment": broken_assessment})
    with pytest.raises(RecommendationInvariantError, match="buffer"):
        _build(broken)


# REC-028
def test_solver_reason_code_mismatch_is_rejected() -> None:
    run = _run()
    altered_solver = run.likely_solver_result.model_copy(
        update={"reason_codes": ("DIFFERENT",)}
    )
    broken = run.model_copy(update={"likely_solver_result": altered_solver})
    with pytest.raises(RecommendationInvariantError, match="reason codes"):
        _build(broken)


# REC-029
def test_assembly_preserves_trace_context() -> None:
    assembly = _build(_run())
    assert assembly.source_competition_id == "cmp-001"
    assert assembly.source_report_version == 3


# REC-030 is covered by RecommendationTraceContext model tests.
# REC-031 is covered by RecommendationPayload model tests.


# REC-032
def test_mutating_public_materialization_does_not_mutate_internal_payload() -> None:
    payload = _build(_run()).recommendation_payload
    assert payload is not None
    public = materialize_public_recommendation(payload)
    public.rationale.append("invented")
    public.suggested_windows.clear()
    assert "invented" not in payload.rationale
    assert payload.suggested_windows


# REC-033 is structurally covered by REC-034: recommendation never calls the solver.


def _availability() -> AvailabilityResult:
    return AvailabilityResult(
        timezone="UTC",
        horizon_start=START,
        horizon_end=START + timedelta(hours=8),
        busy_blocks=(),
        available_blocks=(
            AvailabilityBlock(
                start=START,
                end=START + timedelta(hours=8),
                timezone="UTC",
                source="work-window",
                availability_type=AvailabilityType.AVAILABLE,
            ),
        ),
        daily_capacity=(
            DailyCapacity(
                local_date=date(2026, 10, 1),
                calendar_free_minutes=480,
                accepted_project_minutes=0,
                configured_project_limit_minutes=480,
                remaining_project_capacity_minutes=480,
                usable_project_minutes=480,
            ),
        ),
    )


def _config() -> SolverConfig:
    return SolverConfig(
        submission_deadline=START + timedelta(hours=8),
        buffer_target_minutes=0,
    )


# REC-034
def test_block4_to_block5_integration_keeps_total_solver_calls_at_four(monkeypatch) -> None:
    calls = []

    def fake_solver(_availability, workload, _config):
        calls.append(workload.required_effort.likely_minutes)
        return SolverResult(
            status=SolverRunStatus.OPTIMAL,
            candidate_allocations=(
                CandidateAllocation(
                    candidate_id="candidate-001",
                    work_blocks=(),
                    buffer_minutes=60,
                    hard_constraint_violations=(),
                    assumptions=(),
                ),
            ),
            reason_codes=(),
        )

    monkeypatch.setattr(feasibility_service, "solve_candidate_allocations", fake_solver)

    run = assess_feasibility_run(_availability(), _workload_input(), _config())
    assert len(calls) == 4

    assembly = _build(run)
    assert assembly.recommendation_payload is not None
    assert len(calls) == 4


# REC-035
def test_baseline_and_assessment_assumption_mismatch_is_rejected() -> None:
    original = WorkloadAssumption(description="original")
    different = WorkloadAssumption(description="different")
    run = _run(
        assessment_assumptions=(original,),
        baseline_assumptions=(different,),
    )
    with pytest.raises(RecommendationInvariantError, match="assumptions"):
        _build(run)



# V2 boundary hardening
def test_materialization_revalidates_forged_payload() -> None:
    payload = _build(_run()).recommendation_payload
    assert payload is not None
    forged = payload.model_copy(update={"recommended_candidate_id": ""})
    with pytest.raises(RecommendationInputError, match="materialization"):
        materialize_public_recommendation(forged)
# V3 boundary hardening
def test_materialization_rejects_forged_payload_alternatives() -> None:
    payload = _build(_run()).recommendation_payload
    assert payload is not None
    forged = payload.model_copy(update={"alternatives": ("candidate-002",)})
    with pytest.raises(RecommendationInputError, match="materialization"):
        materialize_public_recommendation(forged)


def test_empty_rendered_rationale_is_normalized_to_invariant_error() -> None:
    run = _run()
    broken_assessment = run.assessment.model_copy(
        update={
            "reason_codes": (),
            "sensitivity_codes": (),
        }
    )
    broken = run.model_copy(update={"assessment": broken_assessment})
    with pytest.raises(
        RecommendationInvariantError,
        match="payload contradicts feasibility evidence",
    ):
        _build(broken)


def test_missing_tradeoff_evidence_is_normalized_to_invariant_error() -> None:
    run = _run(FeasibilityStatus.FEASIBLE_WITH_TRADEOFFS)
    broken_assessment = run.assessment.model_copy(
        update={"tradeoff_codes": ()}
    )
    broken = run.model_copy(update={"assessment": broken_assessment})
    with pytest.raises(
        RecommendationInvariantError,
        match="assembly contradicts feasibility state",
    ):
        _build(broken)


def test_public_materialization_includes_alternative_plan_details() -> None:
    run = _run()
    primary = run.likely_solver_result.candidate_allocations[0]
    extra = _candidate(
        candidate_id="candidate-002",
        work_blocks=(_block(start_offset=30),),
    )
    altered_solver = run.likely_solver_result.model_copy(
        update={"candidate_allocations": (primary, extra)}
    )
    expanded = run.model_copy(update={"likely_solver_result": altered_solver})

    payload = _build(expanded).recommendation_payload
    assert payload is not None
    public = materialize_public_recommendation(payload)

    assert len(public.alternatives) == 1
    assert public.alternatives[0]["candidate_id"] == "candidate-002"
    assert public.alternatives[0]["suggested_windows"]
