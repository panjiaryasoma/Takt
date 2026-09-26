from __future__ import annotations

from datetime import UTC, date, datetime, timedelta

import engine.scheduler.service as scheduler_service
from engine.availability.models import AvailabilityResult, DailyCapacity
from engine.scheduler import SolverConfig, solve_candidate_allocations
from engine.scheduler.cp_sat import RawSolverSolution
from engine.scheduler.models import SolverRunStatus
from engine.scheduler.ranking import rank_candidate_allocations
from engine.workload import analyze_workload
from packages.contracts import (
    AllocationBlock,
    AvailabilityBlock,
    AvailabilityType,
    CandidateAllocation,
    Task,
)
from packages.contracts.workload import WorkloadInput

START = datetime(2026, 10, 1, 9, 0, tzinfo=UTC)


def _block(
    start_minutes: int,
    duration: int = 60,
    *,
    task_id: str = "core",
) -> AllocationBlock:
    start = START + timedelta(minutes=start_minutes)
    return AllocationBlock(
        task_id=task_id,
        start=start,
        end=start + timedelta(minutes=duration),
        allocated_minutes=duration,
        availability_source="window-1",
    )


def _candidate(
    candidate_id: str,
    blocks: tuple[AllocationBlock, ...],
    *,
    violations: tuple[str, ...] = (),
) -> CandidateAllocation:
    return CandidateAllocation(
        candidate_id=candidate_id,
        work_blocks=blocks,
        buffer_minutes=180,
        hard_constraint_violations=violations,
        assumptions=(),
    )


def _availability() -> AvailabilityResult:
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


def _workload():
    return analyze_workload(
        WorkloadInput(
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
    )


def _config() -> SolverConfig:
    return SolverConfig(
        submission_deadline=START + timedelta(hours=4),
        buffer_target_minutes=0,
    )


def test_solver_builds_distinct_valid_candidate_pool_when_slack_exists(monkeypatch) -> None:
    def fake_solver(*_args, materially_distinct_from=(), **_kwargs):
        index = len(materially_distinct_from)
        return RawSolverSolution(
            status=SolverRunStatus.OPTIMAL,
            work_blocks=(_block(index * 30),),
            used_window_ids=("w0",),
            makespan_minutes=60 + index * 30,
        )

    monkeypatch.setattr(scheduler_service, "solve_cp_sat", fake_solver)

    result = solve_candidate_allocations(_availability(), _workload(), _config())

    assert tuple(item.candidate_id for item in result.candidate_allocations) == (
        "candidate-001",
        "candidate-002",
        "candidate-003",
    )
    starts = tuple(
        item.work_blocks[0].start
        for item in result.candidate_allocations
    )
    assert len(set(starts)) == 3
    assert all(item.is_recommendable for item in result.candidate_allocations)


def test_ranking_uses_validity_fragmentation_completion_and_deterministic_signature() -> None:
    early = _candidate("early", (_block(0),))
    late = _candidate("late", (_block(60),))
    fragmented = _candidate(
        "fragmented",
        (
            _block(0, 30),
            _block(60, 30),
        ),
    )
    invalid = _candidate(
        "invalid",
        (_block(0),),
        violations=("BROKEN",),
    )

    ranked = rank_candidate_allocations(
        (fragmented, late, invalid, early)
    )

    assert tuple(item.candidate_id for item in ranked) == (
        "early",
        "late",
        "fragmented",
    )


def test_ranking_deduplicates_identical_schedule_alternatives() -> None:
    first = _candidate("candidate-b", (_block(0),))
    duplicate = _candidate("candidate-a", (_block(0),))
    distinct = _candidate("candidate-c", (_block(60),))

    ranked = rank_candidate_allocations((first, duplicate, distinct))

    assert tuple(item.candidate_id for item in ranked) == (
        "candidate-a",
        "candidate-c",
    )
