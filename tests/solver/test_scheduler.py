from datetime import UTC, date, datetime, timedelta

import pytest

from engine.availability.models import AvailabilityResult, DailyCapacity
from engine.scheduler import SolverConfig, SolverRunStatus, solve_candidate_allocations
from engine.scheduler.service import SolverInputError
from packages.contracts import AvailabilityBlock, AvailabilityType
from packages.contracts.models import Task
from packages.contracts.workload import EffortRange, WorkloadAnalysis

START = datetime(2026, 10, 1, 9, 0, tzinfo=UTC)


def _availability():
    return AvailabilityResult(
        timezone="UTC",
        horizon_start=START,
        horizon_end=START + timedelta(hours=4),
        busy_blocks=(),
        available_blocks=(
            AvailabilityBlock(
                start=START,
                end=START + timedelta(hours=4),
                timezone="UTC",
                source="derived:work_window:0",
                availability_type=AvailabilityType.AVAILABLE,
            ),
        ),
        daily_capacity=(
            DailyCapacity(
                local_date=date(2026, 10, 1),
                calendar_free_minutes=240,
                accepted_project_minutes=0,
                configured_project_limit_minutes=240,
                remaining_project_capacity_minutes=240,
                usable_project_minutes=240,
            ),
        ),
    )


def _workload(minutes=120):
    task = Task(
        task_id="a",
        name="A",
        mandatory=True,
        dependencies=(),
        effort_min_minutes=minutes,
        effort_likely_minutes=minutes,
        effort_max_minutes=minutes,
        assumptions=(),
    )
    effort = EffortRange(
        min_minutes=minutes,
        likely_minutes=minutes,
        max_minutes=minutes,
    )
    return WorkloadAnalysis(
        tasks=(task,),
        topological_order=("a",),
        required_task_ids=("a",),
        declared_mandatory_effort=effort,
        required_effort=effort,
        optional_effort=EffortRange(min_minutes=0, likely_minutes=0, max_minutes=0),
        assumptions=(),
    )


def _config(buffer=0):
    return SolverConfig(
        submission_deadline=START + timedelta(hours=4),
        buffer_target_minutes=buffer,
    )


def test_preflight_returns_explicit_infeasible_for_capacity_shortfall() -> None:
    result = solve_candidate_allocations(_availability(), _workload(240), _config(1))
    assert result.status is SolverRunStatus.INFEASIBLE
    assert result.reason_codes == ("INSUFFICIENT_CAPACITY_BEFORE_DEADLINE",)
    assert result.candidate_allocations == ()


def test_preflight_rejects_tampered_required_closure() -> None:
    workload = _workload()
    tampered = workload.model_copy(update={"required_task_ids": ()})
    with pytest.raises(SolverInputError):
        solve_candidate_allocations(_availability(), tampered, _config())


def test_preflight_rejects_tampered_daily_capacity() -> None:
    availability = _availability()
    row = availability.daily_capacity[0].model_copy(
        update={"usable_project_minutes": 999}
    )
    tampered = availability.model_copy(update={"daily_capacity": (row,)})
    with pytest.raises(SolverInputError):
        solve_candidate_allocations(tampered, _workload(), _config())


def test_preflight_rejects_non_available_block_in_available_collection() -> None:
    availability = _availability()
    block = availability.available_blocks[0].model_copy(
        update={"availability_type": AvailabilityType.FIXED_BUSY}
    )
    tampered = availability.model_copy(update={"available_blocks": (block,)})
    with pytest.raises(SolverInputError):
        solve_candidate_allocations(tampered, _workload(), _config())


def test_preflight_rejects_calendar_free_mismatch() -> None:
    availability = _availability()
    row = availability.daily_capacity[0].model_copy(
        update={
            "calendar_free_minutes": 200,
            "usable_project_minutes": 200,
        }
    )
    tampered = availability.model_copy(update={"daily_capacity": (row,)})
    with pytest.raises(SolverInputError):
        solve_candidate_allocations(tampered, _workload(), _config())


def test_public_boundary_normalizes_invalid_timezone_to_solver_input_error() -> None:
    from zoneinfo import ZoneInfoNotFoundError

    tampered = _availability().model_copy(update={"timezone": "Mars/Olympus"})
    with pytest.raises(SolverInputError) as error:
        solve_candidate_allocations(tampered, _workload(), _config())
    assert isinstance(error.value.__cause__, ZoneInfoNotFoundError)


def test_public_boundary_normalizes_workload_graph_error() -> None:
    from engine.workload.graph import WorkloadDependencyError

    workload = _workload()
    task = workload.tasks[0].model_copy(update={"dependencies": ("missing",)})
    tampered = workload.model_copy(update={"tasks": (task,)})
    with pytest.raises(SolverInputError) as error:
        solve_candidate_allocations(_availability(), tampered, _config())
    assert isinstance(error.value.__cause__, WorkloadDependencyError)


@pytest.mark.parametrize(
    "busy_type",
    (
        AvailabilityType.FIXED_BUSY,
        AvailabilityType.FLEXIBLE_BUSY,
        AvailabilityType.ACCEPTED_PROJECT_COMMITMENT,
    ),
)
def test_preflight_rejects_available_busy_cross_set_overlap(busy_type) -> None:
    availability = _availability()
    busy = AvailabilityBlock(
        start=START + timedelta(hours=1),
        end=START + timedelta(hours=2),
        timezone="UTC",
        source="occupied",
        availability_type=busy_type,
    )
    tampered = availability.model_copy(update={"busy_blocks": (busy,)})
    with pytest.raises(SolverInputError, match="must not overlap busy_blocks"):
        solve_candidate_allocations(tampered, _workload(), _config())


def test_preflight_rejects_tampered_accepted_project_accounting() -> None:
    accepted = AvailabilityBlock(
        start=START - timedelta(hours=1),
        end=START,
        timezone="UTC",
        source="accepted-plan",
        availability_type=AvailabilityType.ACCEPTED_PROJECT_COMMITMENT,
    )
    available = AvailabilityBlock(
        start=START,
        end=START + timedelta(hours=2),
        timezone="UTC",
        source="derived:work_window:0",
        availability_type=AvailabilityType.AVAILABLE,
    )
    tampered = AvailabilityResult(
        timezone="UTC",
        horizon_start=START - timedelta(hours=1),
        horizon_end=START + timedelta(hours=2),
        busy_blocks=(accepted,),
        available_blocks=(available,),
        daily_capacity=(
            DailyCapacity(
                local_date=date(2026, 10, 1),
                calendar_free_minutes=120,
                accepted_project_minutes=0,
                configured_project_limit_minutes=120,
                remaining_project_capacity_minutes=120,
                usable_project_minutes=120,
            ),
        ),
    )
    with pytest.raises(SolverInputError, match="accepted_project_minutes"):
        solve_candidate_allocations(tampered, _workload(60), _config())


def test_public_boundary_normalizes_pydantic_validation_error() -> None:
    from pydantic import ValidationError

    unsafe = SolverConfig.model_construct(
        submission_deadline="not-a-datetime",
        buffer_target_minutes=0,
        effort_basis="LIKELY",
    )
    with pytest.raises(SolverInputError) as error:
        solve_candidate_allocations(_availability(), _workload(), unsafe)
    assert isinstance(error.value.__cause__, ValidationError)


def test_accepted_project_accounting_uses_union_duration() -> None:
    first = AvailabilityBlock(
        start=START - timedelta(hours=1),
        end=START,
        timezone="UTC",
        source="accepted-a",
        availability_type=AvailabilityType.ACCEPTED_PROJECT_COMMITMENT,
    )
    second = AvailabilityBlock(
        start=START - timedelta(minutes=30),
        end=START + timedelta(minutes=30),
        timezone="UTC",
        source="accepted-b",
        availability_type=AvailabilityType.ACCEPTED_PROJECT_COMMITMENT,
    )
    available = AvailabilityBlock(
        start=START + timedelta(minutes=30),
        end=START + timedelta(hours=2, minutes=30),
        timezone="UTC",
        source="derived:work_window:0",
        availability_type=AvailabilityType.AVAILABLE,
    )
    availability = AvailabilityResult(
        timezone="UTC",
        horizon_start=START - timedelta(hours=1),
        horizon_end=START + timedelta(hours=2, minutes=30),
        busy_blocks=(first, second),
        available_blocks=(available,),
        daily_capacity=(
            DailyCapacity(
                local_date=date(2026, 10, 1),
                calendar_free_minutes=120,
                accepted_project_minutes=90,
                configured_project_limit_minutes=180,
                remaining_project_capacity_minutes=90,
                usable_project_minutes=90,
            ),
        ),
    )
    result = solve_candidate_allocations(availability, _workload(120), _config())
    assert result.status is SolverRunStatus.INFEASIBLE
    assert result.reason_codes == ("INSUFFICIENT_CAPACITY_BEFORE_DEADLINE",)
