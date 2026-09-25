from collections import defaultdict
from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo

import pytest

pytest.importorskip("ortools")

from engine.availability.models import AvailabilityResult, DailyCapacity
from engine.scheduler import SolverConfig, SolverRunStatus, solve_candidate_allocations
from engine.scheduler.cp_sat import solve_cp_sat
from engine.workload import analyze_workload
from packages.contracts import AvailabilityBlock, AvailabilityType
from packages.contracts.models import Task
from packages.contracts.workload import WorkloadInput

START = datetime(2026, 10, 1, 9, 0, tzinfo=UTC)


def _task(task_id, minutes, dependencies=(), mandatory=True):
    return Task(
        task_id=task_id,
        name=task_id,
        mandatory=mandatory,
        dependencies=dependencies,
        effort_min_minutes=minutes,
        effort_likely_minutes=minutes,
        effort_max_minutes=minutes,
        assumptions=(),
    )


def _analysis(tasks):
    return analyze_workload(WorkloadInput(tasks=tuple(tasks), assumptions=()))


def _minutes_by_local_day(start, end, zone):
    start_utc = start.astimezone(UTC)
    end_utc = end.astimezone(UTC)
    result = defaultdict(int)
    current = start_utc.astimezone(zone).date()
    final = (end_utc - timedelta(microseconds=1)).astimezone(zone).date()
    while current <= final:
        day_start = datetime.combine(current, time.min, tzinfo=zone).astimezone(UTC)
        day_end = datetime.combine(
            current + timedelta(days=1),
            time.min,
            tzinfo=zone,
        ).astimezone(UTC)
        lower = max(start_utc, day_start)
        upper = min(end_utc, day_end)
        if upper > lower:
            result[current] += int((upper - lower).total_seconds() // 60)
        current += timedelta(days=1)
    return result


def _availability(
    blocks,
    *,
    timezone="UTC",
    limits_by_day=None,
    horizon_start=None,
    horizon_end=None,
):
    zone = ZoneInfo(timezone)
    available = tuple(
        AvailabilityBlock(
            start=start,
            end=end,
            timezone=timezone,
            source=source,
            availability_type=AvailabilityType.AVAILABLE,
        )
        for start, end, source in blocks
    )
    if horizon_start is None:
        horizon_start = min((item[0] for item in blocks), default=START)
    if horizon_end is None:
        horizon_end = max(
            (item[1] for item in blocks),
            default=horizon_start + timedelta(hours=12),
        )

    free = defaultdict(int)
    for start, end, _ in blocks:
        for local_date, minutes in _minutes_by_local_day(start, end, zone).items():
            free[local_date] += minutes

    if limits_by_day is None:
        limits_by_day = {local_date: minutes for local_date, minutes in free.items()}
    all_dates = sorted(set(free) | set(limits_by_day))
    rows = tuple(
        DailyCapacity(
            local_date=local_date,
            calendar_free_minutes=free.get(local_date, 0),
            accepted_project_minutes=0,
            configured_project_limit_minutes=limits_by_day.get(local_date, 0),
            remaining_project_capacity_minutes=limits_by_day.get(local_date, 0),
            usable_project_minutes=min(
                free.get(local_date, 0),
                limits_by_day.get(local_date, 0),
            ),
        )
        for local_date in all_dates
    )
    return AvailabilityResult(
        timezone=timezone,
        horizon_start=horizon_start,
        horizon_end=horizon_end,
        busy_blocks=(),
        available_blocks=available,
        daily_capacity=rows,
    )


def _config(deadline=None, buffer=0):
    return SolverConfig(
        submission_deadline=deadline or START + timedelta(hours=12),
        buffer_target_minutes=buffer,
    )


def test_single_task_fits_one_block() -> None:
    availability = _availability(
        ((START, START + timedelta(hours=4), "window-a"),)
    )
    result = solve_candidate_allocations(
        availability,
        _analysis((_task("a", 120),)),
        _config(),
    )
    assert result.status in {SolverRunStatus.OPTIMAL, SolverRunStatus.FEASIBLE}
    candidate = result.candidate_allocations[0]
    assert sum(block.allocated_minutes for block in candidate.work_blocks) == 120
    assert candidate.hard_constraint_violations == ()


def test_task_can_split_across_available_blocks() -> None:
    availability = _availability(
        (
            (START, START + timedelta(hours=1), "window-a"),
            (
                START + timedelta(hours=2),
                START + timedelta(hours=3),
                "window-b",
            ),
        ),
        limits_by_day={date(2026, 10, 1): 120},
    )
    result = solve_candidate_allocations(
        availability,
        _analysis((_task("a", 120),)),
        _config(),
    )
    candidate = result.candidate_allocations[0]
    assert len(candidate.work_blocks) == 2
    assert sum(block.allocated_minutes for block in candidate.work_blocks) == 120


def test_finish_to_start_dependency_is_respected() -> None:
    availability = _availability(
        ((START, START + timedelta(hours=4), "window-a"),)
    )
    tasks = (_task("a", 60), _task("b", 60, dependencies=("a",)))
    result = solve_candidate_allocations(availability, _analysis(tasks), _config())
    blocks = {block.task_id: block for block in result.candidate_allocations[0].work_blocks}
    assert blocks["b"].start >= blocks["a"].end


def test_daily_capacity_is_respected() -> None:
    availability = _availability(
        ((START, START + timedelta(hours=4), "window-a"),),
        limits_by_day={date(2026, 10, 1): 90},
    )
    result = solve_candidate_allocations(
        availability,
        _analysis((_task("a", 120),)),
        _config(),
    )
    assert result.status is SolverRunStatus.INFEASIBLE


def test_optional_task_is_not_silently_promoted() -> None:
    availability = _availability(
        ((START, START + timedelta(hours=4), "window-a"),)
    )
    tasks = (_task("a", 60), _task("z", 120, mandatory=False))
    result = solve_candidate_allocations(availability, _analysis(tasks), _config())
    task_ids = {block.task_id for block in result.candidate_allocations[0].work_blocks}
    assert task_ids == {"a"}


def test_same_exact_input_produces_same_candidate() -> None:
    availability = _availability(
        ((START, START + timedelta(hours=4), "window-a"),)
    )
    workload = _analysis((_task("a", 60), _task("b", 60)))
    first = solve_candidate_allocations(availability, workload, _config())
    second = solve_candidate_allocations(availability, workload, _config())
    assert first == second


def test_deadline_clips_windows_and_exact_cutoff_is_allowed() -> None:
    deadline = START + timedelta(hours=2)
    availability = _availability(
        ((START, START + timedelta(hours=4), "window-a"),)
    )
    result = solve_candidate_allocations(
        availability,
        _analysis((_task("a", 120),)),
        _config(deadline=deadline),
    )
    candidate = result.candidate_allocations[0]
    assert max(block.end for block in candidate.work_blocks) == deadline


def test_no_available_window_is_explicitly_infeasible() -> None:
    availability = _availability(
        (),
        horizon_start=START,
        horizon_end=START + timedelta(hours=4),
        limits_by_day={date(2026, 10, 1): 0},
    )
    raw = solve_cp_sat(
        availability,
        _analysis((_task("a", 60),)),
        _config(deadline=START + timedelta(hours=4)),
    )
    assert raw.status is SolverRunStatus.INFEASIBLE
    assert raw.work_blocks == ()


def test_multi_day_capacity_is_enforced_per_local_date() -> None:
    next_day = START + timedelta(days=1)
    availability = _availability(
        (
            (START, START + timedelta(hours=2), "day-1"),
            (next_day, next_day + timedelta(hours=2), "day-2"),
        ),
        limits_by_day={
            date(2026, 10, 1): 60,
            date(2026, 10, 2): 60,
        },
        horizon_end=next_day + timedelta(hours=2),
    )
    result = solve_candidate_allocations(
        availability,
        _analysis((_task("a", 120),)),
        _config(deadline=next_day + timedelta(hours=2)),
    )
    candidate = result.candidate_allocations[0]
    by_day = defaultdict(int)
    for block in candidate.work_blocks:
        by_day[block.start.date()] += block.allocated_minutes
    assert dict(by_day) == {date(2026, 10, 1): 60, date(2026, 10, 2): 60}


def test_buffer_target_is_preserved_when_feasible() -> None:
    availability = _availability(
        ((START, START + timedelta(hours=3), "window-a"),),
        limits_by_day={date(2026, 10, 1): 180},
    )
    result = solve_candidate_allocations(
        availability,
        _analysis((_task("a", 120),)),
        _config(deadline=START + timedelta(hours=3), buffer=60),
    )
    candidate = result.candidate_allocations[0]
    assert candidate.buffer_minutes == 60


def test_zero_minute_milestone_preserves_dependency_chain() -> None:
    availability = _availability(
        ((START, START + timedelta(hours=3), "window-a"),)
    )
    tasks = (
        _task("a", 60),
        _task("m", 0, dependencies=("a",)),
        _task("b", 60, dependencies=("m",)),
    )
    result = solve_candidate_allocations(availability, _analysis(tasks), _config())
    blocks = {block.task_id: block for block in result.candidate_allocations[0].work_blocks}
    assert "m" not in blocks
    assert blocks["b"].start >= blocks["a"].end


def test_cross_midnight_timezone_uses_local_day_capacity() -> None:
    zone = ZoneInfo("Asia/Jakarta")
    local_start = datetime(2026, 10, 1, 23, 0, tzinfo=zone)
    local_end = datetime(2026, 10, 2, 1, 0, tzinfo=zone)
    availability = _availability(
        ((local_start, local_end, "cross-midnight"),),
        timezone="Asia/Jakarta",
        limits_by_day={
            date(2026, 10, 1): 60,
            date(2026, 10, 2): 60,
        },
        horizon_start=local_start,
        horizon_end=local_end,
    )
    result = solve_candidate_allocations(
        availability,
        _analysis((_task("a", 120),)),
        _config(deadline=local_end),
    )
    candidate = result.candidate_allocations[0]
    by_day = defaultdict(int)
    for block in candidate.work_blocks:
        by_day[block.start.astimezone(zone).date()] += block.allocated_minutes
    assert dict(by_day) == {date(2026, 10, 1): 60, date(2026, 10, 2): 60}


def test_reordered_semantic_input_produces_same_candidate() -> None:
    first_block = (START, START + timedelta(hours=1), "window-a")
    second_block = (
        START + timedelta(hours=2),
        START + timedelta(hours=3),
        "window-b",
    )
    first_availability = _availability((first_block, second_block))
    second_availability = _availability((second_block, first_block))

    task_a = _task("a", 60)
    task_b = _task("b", 60)
    first_workload = _analysis((task_a, task_b))
    second_workload = _analysis((task_b, task_a))

    first = solve_candidate_allocations(first_availability, first_workload, _config())
    second = solve_candidate_allocations(second_availability, second_workload, _config())
    assert first == second
