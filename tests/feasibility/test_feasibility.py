from __future__ import annotations

from datetime import UTC, date, datetime, timedelta

import pytest

import engine.feasibility.service as feasibility_service
from engine.availability.models import AvailabilityResult, DailyCapacity
from engine.feasibility import (
    FeasibilityExecutionError,
    FeasibilityIndeterminateError,
    FeasibilityInputError,
    FeasibilityInvariantError,
    FeasibilityScenario,
    assess_feasibility,
)
from engine.scheduler.cp_sat import SolverDependencyUnavailableError
from engine.scheduler.models import SolverConfig, SolverResult, SolverRunStatus
from engine.scheduler.service import SolverInputError, SolverInvariantError
from packages.contracts import AvailabilityBlock, AvailabilityType, CandidateAllocation, Task
from packages.contracts.enums import FeasibilityStatus
from packages.contracts.workload import WorkloadAssumption, WorkloadInput

START = datetime(2026, 10, 1, 9, 0, tzinfo=UTC)
FEASIBLE_SOLVER_STATUSES = {SolverRunStatus.OPTIMAL, SolverRunStatus.FEASIBLE}


def _task(
    task_id: str,
    minimum: int,
    likely: int,
    maximum: int,
    *,
    mandatory: bool = True,
    dependencies: tuple[str, ...] = (),
    assumptions: tuple[str, ...] = (),
) -> Task:
    return Task(
        task_id=task_id,
        name=task_id,
        mandatory=mandatory,
        dependencies=dependencies,
        effort_min_minutes=minimum,
        effort_likely_minutes=likely,
        effort_max_minutes=maximum,
        assumptions=assumptions,
    )


def _workload(
    *,
    core: tuple[int, int, int] = (60, 120, 180),
    optional: tuple[int, int, int] | None = (60, 120, 120),
    assumptions: tuple[WorkloadAssumption, ...] = (),
) -> WorkloadInput:
    tasks = [_task("core", *core)]
    if optional is not None:
        tasks.append(_task("optional", *optional, mandatory=False))
    return WorkloadInput(tasks=tuple(tasks), assumptions=assumptions)


def _availability(
    capacity: int,
    *,
    available_minutes: int = 300,
) -> AvailabilityResult:
    horizon_end = START + timedelta(minutes=max(available_minutes, 300))
    if available_minutes:
        blocks = (
            AvailabilityBlock(
                start=START,
                end=START + timedelta(minutes=available_minutes),
                timezone="UTC",
                source="derived:work_window:0",
                availability_type=AvailabilityType.AVAILABLE,
            ),
        )
    else:
        blocks = ()
    return AvailabilityResult(
        timezone="UTC",
        horizon_start=START,
        horizon_end=horizon_end,
        busy_blocks=(),
        available_blocks=blocks,
        daily_capacity=(
            DailyCapacity(
                local_date=date(2026, 10, 1),
                calendar_free_minutes=available_minutes,
                accepted_project_minutes=0,
                configured_project_limit_minutes=capacity,
                remaining_project_capacity_minutes=capacity,
                usable_project_minutes=min(available_minutes, capacity),
            ),
        ),
    )


def _config(*, buffer: int = 0, deadline_minutes: int = 300) -> SolverConfig:
    return SolverConfig(
        submission_deadline=START + timedelta(minutes=deadline_minutes),
        buffer_target_minutes=buffer,
    )


def _fake_solver_result(status: SolverRunStatus) -> SolverResult:
    if status in FEASIBLE_SOLVER_STATUSES:
        candidate = CandidateAllocation(
            candidate_id="candidate-001",
            work_blocks=(),
            buffer_minutes=60,
            hard_constraint_violations=(),
            assumptions=(),
        )
        return SolverResult(
            status=status,
            candidate_allocations=(candidate,),
            reason_codes=(),
        )
    return SolverResult(
        status=status,
        candidate_allocations=(),
        reason_codes=(f"{status.value}_FOR_TEST",),
    )


def _patch_statuses(monkeypatch, statuses: tuple[SolverRunStatus, ...]) -> None:
    iterator = iter(statuses)

    def fake_solver(*_args, **_kwargs):
        return _fake_solver_result(next(iterator))

    monkeypatch.setattr(feasibility_service, "solve_candidate_allocations", fake_solver)


# FEAS-001
def test_all_scenarios_feasible_classifies_feasible() -> None:
    assessment = assess_feasibility(_availability(300), _workload(), _config())
    assert assessment.status is FeasibilityStatus.FEASIBLE
    assert assessment.likely_candidate_id == "candidate-001"
    assert "ALL_REQUIRED_SCENARIOS_FEASIBLE" in assessment.reason_codes
    assert "FULL_SCOPE_LIKELY_FEASIBLE" in assessment.reason_codes


# FEAS-002
def test_max_failure_classifies_tight_capacity() -> None:
    assessment = assess_feasibility(_availability(150), _workload(), _config())
    assert assessment.status is FeasibilityStatus.TIGHT_CAPACITY
    assert "EFFORT_OVERRUN_BREAKS_PLAN" in assessment.sensitivity_codes


# FEAS-003
def test_full_scope_failure_after_max_success_classifies_tradeoff() -> None:
    assessment = assess_feasibility(_availability(200), _workload(), _config())
    assert assessment.status is FeasibilityStatus.FEASIBLE_WITH_TRADEOFFS
    assert assessment.tradeoff_codes == ("OPTIONAL_SCOPE_DOES_NOT_FIT",)


# FEAS-004
def test_likely_failure_classifies_not_feasible() -> None:
    assessment = assess_feasibility(_availability(100), _workload(), _config())
    assert assessment.status is FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS
    assert assessment.likely_candidate_id is None


# FEAS-005
def test_likely_unknown_is_indeterminate(monkeypatch) -> None:
    _patch_statuses(
        monkeypatch,
        (
            SolverRunStatus.OPTIMAL,
            SolverRunStatus.UNKNOWN,
            SolverRunStatus.UNKNOWN,
            SolverRunStatus.UNKNOWN,
        ),
    )
    with pytest.raises(FeasibilityIndeterminateError, match="LIKELY"):
        assess_feasibility(_availability(300), _workload(), _config())


# FEAS-006
def test_min_feasible_likely_infeasible_preserves_sensitivity() -> None:
    workload = _workload(core=(60, 120, 180), optional=None)
    assessment = assess_feasibility(_availability(90), workload, _config())
    assert assessment.status is FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS
    assert "MINIMUM_EFFORT_SCENARIO_FEASIBLE" in assessment.sensitivity_codes
    assert "LIKELY_EFFORT_SCENARIO_INFEASIBLE" in assessment.sensitivity_codes


# FEAS-007
def test_optional_prerequisite_of_mandatory_is_required_not_tradeoff() -> None:
    workload = WorkloadInput(
        tasks=(
            _task("foundation", 30, 30, 30, mandatory=False),
            _task("core", 60, 60, 60, dependencies=("foundation",)),
        )
    )
    assessment = assess_feasibility(_availability(120), workload, _config())
    assert assessment.status is FeasibilityStatus.FEASIBLE
    assert assessment.tradeoff_codes == ()


# FEAS-008
def test_truly_optional_task_not_fitting_is_scope_tradeoff() -> None:
    assessment = assess_feasibility(_availability(200), _workload(), _config())
    assert assessment.tradeoff_codes == ("OPTIONAL_SCOPE_DOES_NOT_FIT",)


# FEAS-009
def test_optional_task_fitting_has_no_scope_tradeoff() -> None:
    assessment = assess_feasibility(_availability(300), _workload(), _config())
    assert assessment.tradeoff_codes == ()


# FEAS-010
def test_buffer_target_can_make_max_tight() -> None:
    assessment = assess_feasibility(
        _availability(240),
        _workload(optional=None),
        _config(buffer=61),
    )
    assert assessment.status is FeasibilityStatus.TIGHT_CAPACITY


# FEAS-011
def test_deadline_can_make_likely_not_feasible() -> None:
    assessment = assess_feasibility(
        _availability(300),
        _workload(optional=None),
        _config(deadline_minutes=90),
    )
    assert assessment.status is FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS


# FEAS-012
def test_zero_availability_is_not_feasible() -> None:
    assessment = assess_feasibility(
        _availability(300, available_minutes=0),
        _workload(optional=None),
        _config(),
    )
    assert assessment.status is FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS


# FEAS-013
def test_semantically_reordered_tasks_produce_identical_assessment() -> None:
    first = _workload()
    second = WorkloadInput(tasks=tuple(reversed(first.tasks)), assumptions=first.assumptions)
    assert assess_feasibility(_availability(300), first, _config()) == assess_feasibility(
        _availability(300), second, _config()
    )


# FEAS-014
def test_baseline_assumptions_remain_traceable_without_duplication() -> None:
    workload = WorkloadInput(
        tasks=(
            _task(
                "core",
                60,
                120,
                180,
                assumptions=("task assumption",),
            ),
        ),
        assumptions=(WorkloadAssumption(description="global assumption"),),
    )
    assessment = assess_feasibility(_availability(240), workload, _config())
    assert [(item.task_id, item.description) for item in assessment.assumptions] == [
        (None, "global assumption"),
        ("core", "task assumption"),
    ]


# FEAS-015
def test_hard_violation_candidate_is_rejected(monkeypatch) -> None:
    candidate = CandidateAllocation(
        candidate_id="candidate-001",
        work_blocks=(),
        buffer_minutes=0,
        hard_constraint_violations=("BROKEN",),
        assumptions=(),
    )
    result = SolverResult(
        status=SolverRunStatus.OPTIMAL,
        candidate_allocations=(candidate,),
        reason_codes=(),
    )
    monkeypatch.setattr(
        feasibility_service,
        "solve_candidate_allocations",
        lambda *_args, **_kwargs: result,
    )
    with pytest.raises(FeasibilityInvariantError, match="hard-constraint"):
        assess_feasibility(_availability(300), _workload(), _config())


# FEAS-016
def test_max_unknown_is_indeterminate_only_after_likely_feasible(monkeypatch) -> None:
    _patch_statuses(
        monkeypatch,
        (
            SolverRunStatus.OPTIMAL,
            SolverRunStatus.OPTIMAL,
            SolverRunStatus.UNKNOWN,
            SolverRunStatus.UNKNOWN,
        ),
    )
    with pytest.raises(FeasibilityIndeterminateError, match="MAX"):
        assess_feasibility(_availability(300), _workload(), _config())


# FEAS-017
def test_full_unknown_is_indeterminate_after_likely_and_max_feasible(monkeypatch) -> None:
    _patch_statuses(
        monkeypatch,
        (
            SolverRunStatus.OPTIMAL,
            SolverRunStatus.OPTIMAL,
            SolverRunStatus.OPTIMAL,
            SolverRunStatus.UNKNOWN,
        ),
    )
    with pytest.raises(FeasibilityIndeterminateError, match="FULL_SCOPE"):
        assess_feasibility(_availability(300), _workload(), _config())


# FEAS-018
def test_min_unknown_does_not_block_primary_classification(monkeypatch) -> None:
    _patch_statuses(
        monkeypatch,
        (
            SolverRunStatus.UNKNOWN,
            SolverRunStatus.OPTIMAL,
            SolverRunStatus.OPTIMAL,
            SolverRunStatus.OPTIMAL,
        ),
    )
    assessment = assess_feasibility(_availability(300), _workload(), _config())
    assert assessment.status is FeasibilityStatus.FEASIBLE
    assert "MIN_SCENARIO_UNKNOWN" in assessment.sensitivity_codes
    assert "ALL_REQUIRED_SCENARIOS_FEASIBLE" not in assessment.reason_codes


# FEAS-019
def test_max_feasible_while_likely_infeasible_is_invariant_failure(monkeypatch) -> None:
    _patch_statuses(
        monkeypatch,
        (
            SolverRunStatus.OPTIMAL,
            SolverRunStatus.INFEASIBLE,
            SolverRunStatus.OPTIMAL,
            SolverRunStatus.UNKNOWN,
        ),
    )
    with pytest.raises(FeasibilityInvariantError, match="monotonicity"):
        assess_feasibility(_availability(300), _workload(), _config())


# FEAS-020
def test_likely_feasible_while_min_infeasible_is_invariant_failure(monkeypatch) -> None:
    _patch_statuses(
        monkeypatch,
        (
            SolverRunStatus.INFEASIBLE,
            SolverRunStatus.OPTIMAL,
            SolverRunStatus.OPTIMAL,
            SolverRunStatus.OPTIMAL,
        ),
    )
    with pytest.raises(FeasibilityInvariantError, match="monotonicity"):
        assess_feasibility(_availability(300), _workload(), _config())


# FEAS-021
def test_full_feasible_while_likely_infeasible_is_invariant_failure(monkeypatch) -> None:
    _patch_statuses(
        monkeypatch,
        (
            SolverRunStatus.OPTIMAL,
            SolverRunStatus.INFEASIBLE,
            SolverRunStatus.INFEASIBLE,
            SolverRunStatus.OPTIMAL,
        ),
    )
    with pytest.raises(FeasibilityInvariantError, match="monotonicity"):
        assess_feasibility(_availability(300), _workload(), _config())


# FEAS-022
def test_feasibility_run_does_not_mutate_source_workload() -> None:
    workload = _workload()
    before = workload.model_dump(mode="python")
    assess_feasibility(_availability(300), workload, _config())
    assert workload.model_dump(mode="python") == before


# FEAS-023
def test_full_scope_goes_through_block_2_requiredness() -> None:
    workload = _workload()
    full = feasibility_service.analyze_scenario(workload, FeasibilityScenario.FULL_SCOPE_LIKELY)
    assert full.required_task_ids == ("core", "optional")


# FEAS-024
def test_scenario_and_code_order_is_deterministic() -> None:
    assessment = assess_feasibility(_availability(150), _workload(), _config())
    assert tuple(item.scenario for item in assessment.scenario_results) == (
        FeasibilityScenario.MIN,
        FeasibilityScenario.LIKELY,
        FeasibilityScenario.MAX,
        FeasibilityScenario.FULL_SCOPE_LIKELY,
    )
    assert assessment.reason_codes == (
        "REQUIRED_MAX_INFEASIBLE",
        "FULL_SCOPE_LIKELY_INFEASIBLE",
    )
    assert assessment.tradeoff_codes == ("OPTIONAL_SCOPE_DOES_NOT_FIT",)
    assert assessment.sensitivity_codes == (
        "MINIMUM_EFFORT_SCENARIO_FEASIBLE",
        "EFFORT_OVERRUN_BREAKS_PLAN",
    )


# FEAS-025
def test_tight_status_keeps_optional_scope_tradeoff_evidence() -> None:
    assessment = assess_feasibility(_availability(150), _workload(), _config())
    assert assessment.status is FeasibilityStatus.TIGHT_CAPACITY
    assert assessment.tradeoff_codes == ("OPTIONAL_SCOPE_DOES_NOT_FIT",)


# FEAS-026
def test_likely_infeasible_ignores_later_unknown_for_primary_status(monkeypatch) -> None:
    _patch_statuses(
        monkeypatch,
        (
            SolverRunStatus.OPTIMAL,
            SolverRunStatus.INFEASIBLE,
            SolverRunStatus.UNKNOWN,
            SolverRunStatus.UNKNOWN,
        ),
    )
    assessment = assess_feasibility(_availability(300), _workload(), _config())
    assert assessment.status is FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS


# FEAS-027
def test_solver_input_failure_is_not_domain_infeasible(monkeypatch) -> None:
    def fail(*_args, **_kwargs):
        raise SolverInputError("bad input")

    monkeypatch.setattr(feasibility_service, "solve_candidate_allocations", fail)
    with pytest.raises(FeasibilityInputError):
        assess_feasibility(_availability(300), _workload(), _config())


# FEAS-028
@pytest.mark.parametrize(
    "error",
    (
        SolverInvariantError("broken invariant"),
        SolverDependencyUnavailableError("missing dependency"),
        RuntimeError("unexpected scheduler failure"),
    ),
)
def test_solver_execution_failure_is_not_domain_infeasible(monkeypatch, error) -> None:
    def fail(*_args, **_kwargs):
        raise error

    monkeypatch.setattr(feasibility_service, "solve_candidate_allocations", fail)
    with pytest.raises(FeasibilityExecutionError):
        assess_feasibility(_availability(300), _workload(), _config())
