"""Independent post-solver hard-constraint verification."""

from __future__ import annotations

from collections import defaultdict
from datetime import UTC, date, datetime, time, timedelta
from itertools import pairwise
from zoneinfo import ZoneInfo

from engine.availability.models import AvailabilityResult
from engine.scheduler.models import SolverConfig
from packages.contracts.enums import AvailabilityType
from packages.contracts.models import AllocationBlock, CandidateAllocation, Task
from packages.contracts.workload import WorkloadAnalysis


def candidate_hard_constraint_violations(
    candidate: CandidateAllocation,
    availability: AvailabilityResult,
    workload: WorkloadAnalysis,
    config: SolverConfig,
) -> tuple[str, ...]:
    """Return deterministic hard-constraint violation codes for a candidate."""

    violations: set[str] = set()
    zone = ZoneInfo(availability.timezone)
    deadline_utc = config.submission_deadline.astimezone(UTC)
    horizon_start_utc = availability.horizon_start.astimezone(UTC)
    horizon_end_utc = availability.horizon_end.astimezone(UTC)
    effective_end_utc = min(deadline_utc, horizon_end_utc)

    task_by_id = {task.task_id: task for task in workload.tasks}
    required_ids = set(workload.required_task_ids)

    _check_known_tasks(candidate, task_by_id, violations)
    _check_block_geometry(candidate, violations)
    _check_no_overlap(candidate, violations)
    _check_availability(candidate, availability, effective_end_utc, violations)
    _check_required_effort(candidate, task_by_id, required_ids, violations)
    _check_dependencies(candidate, task_by_id, required_ids, horizon_start_utc, violations)
    _check_daily_capacity(candidate, availability, zone, violations)
    _check_buffer(candidate, availability, config, effective_end_utc, zone, violations)

    if candidate.hard_constraint_violations:
        violations.add("CANDIDATE_DECLARED_HARD_VIOLATION")

    return tuple(sorted(violations))


def _check_known_tasks(
    candidate: CandidateAllocation,
    task_by_id: dict[str, Task],
    violations: set[str],
) -> None:
    for block in candidate.work_blocks:
        if block.task_id not in task_by_id:
            violations.add("UNKNOWN_TASK")


def _check_block_geometry(
    candidate: CandidateAllocation,
    violations: set[str],
) -> None:
    for block in candidate.work_blocks:
        duration = _minutes(block.start, block.end)
        if duration != block.allocated_minutes:
            violations.add("ALLOCATION_DURATION_MISMATCH")


def _check_no_overlap(
    candidate: CandidateAllocation,
    violations: set[str],
) -> None:
    ordered = sorted(
        candidate.work_blocks,
        key=lambda item: (item.start.astimezone(UTC), item.task_id),
    )
    for previous, current in pairwise(ordered):
        if current.start.astimezone(UTC) < previous.end.astimezone(UTC):
            violations.add("ALLOCATION_OVERLAP")


def _check_availability(
    candidate: CandidateAllocation,
    availability: AvailabilityResult,
    effective_end_utc: datetime,
    violations: set[str],
) -> None:
    available = [
        block
        for block in availability.available_blocks
        if block.availability_type is AvailabilityType.AVAILABLE
    ]
    busy = [
        block
        for block in availability.busy_blocks
        if block.availability_type is not AvailabilityType.AVAILABLE
    ]
    for block in candidate.work_blocks:
        start_utc = block.start.astimezone(UTC)
        end_utc = block.end.astimezone(UTC)
        if end_utc > effective_end_utc:
            violations.add("DEADLINE_VIOLATION")
        containing = [
            window for window in available if _contains(window, start_utc, end_utc)
        ]
        if not containing:
            violations.add("OUTSIDE_AVAILABLE_BLOCK")
        elif not any(window.source == block.availability_source for window in containing):
            violations.add("AVAILABILITY_SOURCE_MISMATCH")
        if any(_overlaps(window, start_utc, end_utc) for window in busy):
            violations.add("BUSY_OVERLAP")


def _check_required_effort(
    candidate: CandidateAllocation,
    task_by_id: dict[str, Task],
    required_ids: set[str],
    violations: set[str],
) -> None:
    allocated: dict[str, int] = defaultdict(int)
    for block in candidate.work_blocks:
        allocated[block.task_id] += block.allocated_minutes

    for task_id in sorted(required_ids):
        task = task_by_id[task_id]
        if allocated[task_id] != task.effort_likely_minutes:
            violations.add(f"REQUIRED_EFFORT_MISMATCH:{task_id}")

    for task_id in sorted(set(allocated) - required_ids):
        if allocated[task_id] > 0:
            violations.add(f"NON_REQUIRED_TASK_ALLOCATED:{task_id}")


def _check_dependencies(
    candidate: CandidateAllocation,
    task_by_id: dict[str, Task],
    required_ids: set[str],
    horizon_start_utc: datetime,
    violations: set[str],
) -> None:
    task_times = _task_times(candidate, task_by_id, required_ids, horizon_start_utc)
    for task_id in sorted(required_ids):
        task = task_by_id[task_id]
        task_start, _ = task_times[task_id]
        for dependency in task.dependencies:
            if dependency not in required_ids:
                violations.add(f"REQUIRED_DEPENDENCY_MISSING:{task_id}:{dependency}")
                continue
            _, dependency_end = task_times[dependency]
            if task_start < dependency_end:
                violations.add(f"DEPENDENCY_ORDER:{dependency}->{task_id}")


def _task_times(
    candidate: CandidateAllocation,
    task_by_id: dict[str, Task],
    required_ids: set[str],
    horizon_start_utc: datetime,
) -> dict[str, tuple[datetime, datetime]]:
    starts: dict[str, list[datetime]] = defaultdict(list)
    ends: dict[str, list[datetime]] = defaultdict(list)
    for block in candidate.work_blocks:
        starts[block.task_id].append(block.start.astimezone(UTC))
        ends[block.task_id].append(block.end.astimezone(UTC))

    result: dict[str, tuple[datetime, datetime]] = {}
    unresolved = set(required_ids)
    while unresolved:
        progressed = False
        for task_id in sorted(unresolved):
            task = task_by_id[task_id]
            if task.effort_likely_minutes > 0:
                if not starts[task_id]:
                    continue
                result[task_id] = (min(starts[task_id]), max(ends[task_id]))
                unresolved.remove(task_id)
                progressed = True
                break

            if not all(dependency in result for dependency in task.dependencies):
                continue
            instant = max(
                (result[dependency][1] for dependency in task.dependencies),
                default=horizon_start_utc,
            )
            result[task_id] = (instant, instant)
            unresolved.remove(task_id)
            progressed = True
            break

        if not progressed:
            for task_id in unresolved:
                result[task_id] = (horizon_start_utc, horizon_start_utc)
            break
    return result


def _check_daily_capacity(
    candidate: CandidateAllocation,
    availability: AvailabilityResult,
    zone: ZoneInfo,
    violations: set[str],
) -> None:
    limits = {item.local_date: item.usable_project_minutes for item in availability.daily_capacity}
    allocated: dict[date, int] = defaultdict(int)
    for block in candidate.work_blocks:
        for local_date, minutes in _minutes_by_local_day(block, zone).items():
            allocated[local_date] += minutes

    for local_date, minutes in allocated.items():
        if minutes > limits.get(local_date, 0):
            violations.add(f"DAILY_CAPACITY:{local_date.isoformat()}")


def _check_buffer(
    candidate: CandidateAllocation,
    availability: AvailabilityResult,
    config: SolverConfig,
    effective_end_utc: datetime,
    zone: ZoneInfo,
    violations: set[str],
) -> None:
    capacity = effective_capacity_before_deadline(availability, effective_end_utc, zone)
    allocated = sum(block.allocated_minutes for block in candidate.work_blocks)
    actual_buffer = max(capacity - allocated, 0)
    if candidate.buffer_minutes != actual_buffer:
        violations.add("BUFFER_ACCOUNTING_MISMATCH")
    if actual_buffer < config.buffer_target_minutes:
        violations.add("BUFFER_TARGET_NOT_MET")


def effective_capacity_before_deadline(
    availability: AvailabilityResult,
    effective_end_utc: datetime,
    zone: ZoneInfo,
) -> int:
    """Return project capacity that actually exists before the effective deadline."""

    available_by_day: dict[date, int] = defaultdict(int)
    for block in availability.available_blocks:
        start_utc = block.start.astimezone(UTC)
        end_utc = min(block.end.astimezone(UTC), effective_end_utc)
        if end_utc <= start_utc:
            continue
        clipped = AllocationBlock(
            task_id="capacity-probe",
            start=start_utc.astimezone(zone),
            end=end_utc.astimezone(zone),
            allocated_minutes=_minutes(start_utc, end_utc),
            availability_source=block.source,
        )
        for local_date, minutes in _minutes_by_local_day(clipped, zone).items():
            available_by_day[local_date] += minutes

    capacity_by_day = {
        item.local_date: min(item.usable_project_minutes, available_by_day[item.local_date])
        for item in availability.daily_capacity
    }
    return sum(capacity_by_day.values())


def _minutes_by_local_day(
    block: AllocationBlock,
    zone: ZoneInfo,
) -> dict[date, int]:
    start_utc = block.start.astimezone(UTC)
    end_utc = block.end.astimezone(UTC)
    result: dict[date, int] = defaultdict(int)
    current_date = start_utc.astimezone(zone).date()
    final_date = (end_utc - timedelta(microseconds=1)).astimezone(zone).date()

    while current_date <= final_date:
        day_start_local = datetime.combine(current_date, time.min, tzinfo=zone)
        day_end_local = datetime.combine(
            current_date + timedelta(days=1),
            time.min,
            tzinfo=zone,
        )
        lower = max(start_utc, day_start_local.astimezone(UTC))
        upper = min(end_utc, day_end_local.astimezone(UTC))
        if upper > lower:
            result[current_date] += _minutes(lower, upper)
        current_date += timedelta(days=1)
    return dict(result)



def _overlaps(window, start_utc: datetime, end_utc: datetime) -> bool:
    window_start = window.start.astimezone(UTC)
    window_end = window.end.astimezone(UTC)
    return start_utc < window_end and window_start < end_utc

def _contains(window, start_utc: datetime, end_utc: datetime) -> bool:
    return (
        window.start.astimezone(UTC) <= start_utc
        and end_utc <= window.end.astimezone(UTC)
    )


def _minutes(start: datetime, end: datetime) -> int:
    seconds = (end.astimezone(UTC) - start.astimezone(UTC)).total_seconds()
    return int(seconds // 60)
