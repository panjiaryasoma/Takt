from __future__ import annotations

from datetime import UTC, date, datetime, timedelta

import engine.feasibility.service as feasibility_service
from engine.availability.models import AvailabilityResult, DailyCapacity
from engine.feasibility import assess_feasibility_run
from engine.scheduler.models import SolverConfig, SolverResult, SolverRunStatus
from packages.contracts import (
    AllocationBlock,
    AvailabilityBlock,
    AvailabilityType,
    CandidateAllocation,
    Task,
)
from packages.contracts.enums import FeasibilityStatus
from packages.contracts.workload import WorkloadInput

START = datetime(2026, 10, 1, 9, 0, tzinfo=UTC)


def _candidate(candidate_id: str, start_minutes: int) -> CandidateAllocation:
    start = START + timedelta(minutes=start_minutes)
    return CandidateAllocation(
        candidate_id=candidate_id,
        work_blocks=(
            AllocationBlock(
                task_id="core",
                start=start,
                end=start + timedelta(minutes=60),
                allocated_minutes=60,
                availability_source="window-1",
            ),
        ),
        buffer_minutes=180,
        hard_constraint_violations=(),
        assumptions=(),
    )


def test_feasibility_accepts_candidate_pool_and_uses_ranked_primary(monkeypatch) -> None:
    later = _candidate("candidate-001", 60)
    earlier = _candidate("candidate-002", 0)
    result = SolverResult(
        status=SolverRunStatus.OPTIMAL,
        candidate_allocations=(later, earlier),
        reason_codes=(),
    )
    monkeypatch.setattr(
        feasibility_service,
        "solve_candidate_allocations",
        lambda *_args, **_kwargs: result,
    )

    availability = AvailabilityResult(
        timezone="UTC",
        horizon_start=START,
        horizon_end=START + timedelta(hours=4),
        busy_blocks=(),
        available_blocks=(
            AvailabilityBlock(
                start=START,
                end=START + timedelta(hours=4),
                timezone="UTC",
                source="window-1",
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
    workload = WorkloadInput(
        tasks=(
            Task(
                task_id="core",
                name="Core",
                mandatory=True,
                dependencies=(),
                effort_min_minutes=60,
                effort_likely_minutes=60,
                effort_max_minutes=60,
                assumptions=(),
            ),
        )
    )
    config = SolverConfig(
        submission_deadline=START + timedelta(hours=4),
        buffer_target_minutes=0,
    )

    run = assess_feasibility_run(availability, workload, config)

    assert run.assessment.status is FeasibilityStatus.FEASIBLE
    assert run.assessment.likely_candidate_id == "candidate-002"
    assert len(run.likely_solver_result.candidate_allocations) == 2
