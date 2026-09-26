"""Public orchestration for Block 3 CP-SAT candidate allocation."""

from __future__ import annotations

from collections import defaultdict
from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import ValidationError

from engine.availability.models import AvailabilityResult
from engine.scheduler.cp_sat import RawSolverSolution, solve_cp_sat
from engine.scheduler.invariants import (
    candidate_hard_constraint_violations,
    effective_capacity_before_deadline,
)
from engine.scheduler.models import SolverConfig, SolverResult, SolverRunStatus
from engine.workload.graph import (
    WorkloadGraphError,
    build_dependency_graph,
    required_task_closure,
)
from packages.contracts.enums import AvailabilityType
from packages.contracts.models import CandidateAllocation
from packages.contracts.workload import EffortRange, WorkloadAnalysis


class SolverInputError(ValueError):
    """Raised when upstream Block 1/2 outputs are internally inconsistent."""


class SolverInvariantError(RuntimeError):
    """Raised when CP-SAT output fails the independent invariant checker."""


def solve_candidate_allocations(
    availability: AvailabilityResult,
    workload: WorkloadAnalysis,
    config: SolverConfig,
) -> SolverResult:
    """Build a deterministic pool of valid required-task candidates without committing."""

    try:
        availability = AvailabilityResult.model_validate(
            availability.model_dump(mode="python", warnings=False)
        )
        workload = WorkloadAnalysis.model_validate(
            workload.model_dump(mode="python", warnings=False)
        )
        config = SolverConfig.model_validate(
            config.model_dump(mode="python", warnings=False)
        )
        _validate_upstream_semantics(availability, workload, config)
    except SolverInputError:
        raise
    except (ValidationError, ZoneInfoNotFoundError, WorkloadGraphError) as exc:
        raise SolverInputError(f"invalid solver input: {exc}") from exc

    effective_end_utc = min(
        config.submission_deadline.astimezone(UTC),
        availability.horizon_end.astimezone(UTC),
    )
    if effective_end_utc <= availability.horizon_start.astimezone(UTC):
        return SolverResult(
            status=SolverRunStatus.INFEASIBLE,
            candidate_allocations=(),
            reason_codes=("DEADLINE_BEFORE_PLANNING_HORIZON",),
        )

    zone = ZoneInfo(availability.timezone)
    capacity = effective_capacity_before_deadline(availability, effective_end_utc, zone)
    required_minutes = workload.required_effort.likely_minutes
    if required_minutes + config.buffer_target_minutes > capacity:
        return SolverResult(
            status=SolverRunStatus.INFEASIBLE,
            candidate_allocations=(),
            reason_codes=("INSUFFICIENT_CAPACITY_BEFORE_DEADLINE",),
        )

    raw_solutions = _solve_candidate_pool(
        availability,
        workload,
        config,
    )
    primary = raw_solutions[0]
    if primary.status is SolverRunStatus.INFEASIBLE:
        return SolverResult(
            status=primary.status,
            candidate_allocations=(),
            reason_codes=("CP_SAT_INFEASIBLE",),
        )
    if primary.status is SolverRunStatus.UNKNOWN:
        return SolverResult(
            status=primary.status,
            candidate_allocations=(),
            reason_codes=("CP_SAT_UNKNOWN",),
        )

    candidates = tuple(
        _candidate_from_raw(
            raw,
            index,
            capacity,
            required_minutes,
            workload,
            availability,
            config,
        )
        for index, raw in enumerate(raw_solutions, start=1)
    )
    return SolverResult(
        status=primary.status,
        candidate_allocations=candidates,
        reason_codes=(),
    )


_MAX_CANDIDATES = 3


def _solve_candidate_pool(
    availability: AvailabilityResult,
    workload: WorkloadAnalysis,
    config: SolverConfig,
) -> tuple[RawSolverSolution, ...]:
    solutions: list[RawSolverSolution] = []
    seen_signatures = set()

    while len(solutions) < _MAX_CANDIDATES:
        raw = solve_cp_sat(
            availability,
            workload,
            config,
            materially_distinct_from=tuple(solutions),
        )
        if not solutions:
            solutions.append(raw)
            if raw.status not in {
                SolverRunStatus.OPTIMAL,
                SolverRunStatus.FEASIBLE,
            }:
                break
            if not raw.work_blocks:
                break
            seen_signatures.add(_raw_solution_signature(raw))
            continue

        if raw.status not in {
            SolverRunStatus.OPTIMAL,
            SolverRunStatus.FEASIBLE,
        }:
            break

        signature = _raw_solution_signature(raw)
        if signature in seen_signatures:
            break
        seen_signatures.add(signature)
        solutions.append(raw)

    return tuple(solutions)


def _raw_solution_signature(raw: RawSolverSolution):
    return tuple(
        (
            block.task_id,
            block.start.astimezone(UTC),
            block.end.astimezone(UTC),
            block.allocated_minutes,
            block.availability_source,
        )
        for block in raw.work_blocks
    )


def _candidate_from_raw(
    raw: RawSolverSolution,
    index: int,
    capacity: int,
    required_minutes: int,
    workload: WorkloadAnalysis,
    availability: AvailabilityResult,
    config: SolverConfig,
) -> CandidateAllocation:
    candidate = CandidateAllocation(
        candidate_id=f"candidate-{index:03d}",
        work_blocks=raw.work_blocks,
        buffer_minutes=max(capacity - required_minutes, 0),
        hard_constraint_violations=(),
        assumptions=_candidate_assumptions(workload),
    )
    _raise_on_candidate_violations(
        candidate,
        availability,
        workload,
        config,
    )
    return candidate


def _raise_on_candidate_violations(
    candidate: CandidateAllocation,
    availability: AvailabilityResult,
    workload: WorkloadAnalysis,
    config: SolverConfig,
) -> None:
    violations = candidate_hard_constraint_violations(
        candidate,
        availability,
        workload,
        config,
    )
    if violations:
        joined = ", ".join(violations)
        raise SolverInvariantError(f"post-solver invariant failure: {joined}")


def _validate_upstream_semantics(
    availability: AvailabilityResult,
    workload: WorkloadAnalysis,
    config: SolverConfig,
) -> None:
    graph = build_dependency_graph(workload.tasks)
    expected_required = required_task_closure(workload.tasks, graph)
    if workload.topological_order != graph.topological_order:
        raise SolverInputError("workload topological_order does not match task graph")
    if workload.required_task_ids != expected_required:
        raise SolverInputError("workload required_task_ids does not match dependency closure")

    required_set = set(expected_required)
    required_tasks = tuple(
        task for task in workload.tasks if task.task_id in required_set
    )
    expected_required_effort = _sum_effort(required_tasks)
    if workload.required_effort != expected_required_effort:
        raise SolverInputError("workload required_effort does not match required tasks")

    if config.submission_deadline.second != 0:
        raise SolverInputError("submission deadline must be minute-aligned")

    zone = ZoneInfo(availability.timezone)
    _validate_availability_semantics(availability, zone)
    _validate_capacity_rows(availability, zone)


def _validate_availability_semantics(
    availability: AvailabilityResult,
    zone: ZoneInfo,
) -> None:
    horizon_start = availability.horizon_start.astimezone(UTC)
    horizon_end = availability.horizon_end.astimezone(UTC)
    available = sorted(
        availability.available_blocks,
        key=lambda block: (block.start.astimezone(UTC), block.end.astimezone(UTC)),
    )
    busy = sorted(
        availability.busy_blocks,
        key=lambda block: (block.start.astimezone(UTC), block.end.astimezone(UTC)),
    )

    previous_end = None
    for block in available:
        if block.availability_type is not AvailabilityType.AVAILABLE:
            raise SolverInputError("available_blocks must contain only AVAILABLE blocks")
        start = block.start.astimezone(UTC)
        end = block.end.astimezone(UTC)
        if start < horizon_start or end > horizon_end:
            raise SolverInputError("available block must stay inside availability horizon")
        if previous_end is not None and start < previous_end:
            raise SolverInputError("available blocks must not overlap")
        previous_end = end

    for block in busy:
        if block.availability_type is AvailabilityType.AVAILABLE:
            raise SolverInputError("busy_blocks must not contain AVAILABLE blocks")

    _validate_available_busy_disjoint(available, busy)

    free_by_day = _available_minutes_by_day(available, zone)
    rows = {item.local_date: item for item in availability.daily_capacity}
    all_dates = set(rows) | set(free_by_day)
    for local_date in all_dates:
        row = rows.get(local_date)
        if row is None:
            raise SolverInputError("daily_capacity must cover every available local date")
        if row.calendar_free_minutes != free_by_day.get(local_date, 0):
            raise SolverInputError("daily calendar_free_minutes do not match available blocks")


def _validate_available_busy_disjoint(available, busy) -> None:
    available_index = 0
    busy_index = 0
    while available_index < len(available) and busy_index < len(busy):
        free = available[available_index]
        occupied = busy[busy_index]
        free_start = free.start.astimezone(UTC)
        free_end = free.end.astimezone(UTC)
        busy_start = occupied.start.astimezone(UTC)
        busy_end = occupied.end.astimezone(UTC)

        if free_start < busy_end and busy_start < free_end:
            raise SolverInputError("available_blocks must not overlap busy_blocks")
        if free_end <= busy_end:
            available_index += 1
        else:
            busy_index += 1


def _available_minutes_by_day(blocks, zone: ZoneInfo) -> dict[date, int]:
    result: dict[date, int] = defaultdict(int)
    for block in blocks:
        start_utc = block.start.astimezone(UTC)
        end_utc = block.end.astimezone(UTC)
        for local_date, minutes in _interval_minutes_by_local_day(
            start_utc,
            end_utc,
            zone,
        ).items():
            result[local_date] += minutes
    return dict(result)


def _accepted_project_minutes_by_day(
    availability: AvailabilityResult,
    zone: ZoneInfo,
) -> dict[date, int]:
    intervals_by_day: dict[date, list[tuple[datetime, datetime]]] = defaultdict(list)
    for block in availability.busy_blocks:
        if block.availability_type is not AvailabilityType.ACCEPTED_PROJECT_COMMITMENT:
            continue
        start_utc = block.start.astimezone(UTC)
        end_utc = block.end.astimezone(UTC)
        current_date = start_utc.astimezone(zone).date()
        final_date = (end_utc - timedelta(microseconds=1)).astimezone(zone).date()
        while current_date <= final_date:
            day_start = datetime.combine(current_date, time.min, tzinfo=zone).astimezone(UTC)
            day_end = datetime.combine(
                current_date + timedelta(days=1),
                time.min,
                tzinfo=zone,
            ).astimezone(UTC)
            lower = max(start_utc, day_start)
            upper = min(end_utc, day_end)
            if upper > lower:
                intervals_by_day[current_date].append((lower, upper))
            current_date += timedelta(days=1)

    result: dict[date, int] = {}
    for local_date, intervals in intervals_by_day.items():
        merged: list[tuple[datetime, datetime]] = []
        for start, end in sorted(intervals):
            if not merged or start >= merged[-1][1]:
                merged.append((start, end))
                continue
            previous_start, previous_end = merged[-1]
            merged[-1] = (previous_start, max(previous_end, end))
        result[local_date] = sum(
            int((end - start).total_seconds() // 60) for start, end in merged
        )
    return result


def _interval_minutes_by_local_day(
    start_utc: datetime,
    end_utc: datetime,
    zone: ZoneInfo,
) -> dict[date, int]:
    result: dict[date, int] = defaultdict(int)
    current_date = start_utc.astimezone(zone).date()
    final_date = (end_utc - timedelta(microseconds=1)).astimezone(zone).date()
    while current_date <= final_date:
        day_start = datetime.combine(current_date, time.min, tzinfo=zone).astimezone(UTC)
        day_end = datetime.combine(
            current_date + timedelta(days=1),
            time.min,
            tzinfo=zone,
        ).astimezone(UTC)
        lower = max(start_utc, day_start)
        upper = min(end_utc, day_end)
        if upper > lower:
            result[current_date] += int((upper - lower).total_seconds() // 60)
        current_date += timedelta(days=1)
    return dict(result)


def _validate_capacity_rows(
    availability: AvailabilityResult,
    zone: ZoneInfo,
) -> None:
    seen_dates = set()
    rows = {item.local_date: item for item in availability.daily_capacity}
    accepted_by_day = _accepted_project_minutes_by_day(availability, zone)

    missing_rows = set(accepted_by_day) - set(rows)
    if missing_rows:
        raise SolverInputError(
            "daily_capacity must cover every accepted project commitment local date"
        )

    for item in availability.daily_capacity:
        if item.local_date in seen_dates:
            raise SolverInputError("daily_capacity local_date values must be unique")
        seen_dates.add(item.local_date)

        expected_accepted = accepted_by_day.get(item.local_date, 0)
        if item.accepted_project_minutes != expected_accepted:
            raise SolverInputError(
                "daily accepted_project_minutes do not match accepted commitments"
            )

        expected_remaining = max(
            item.configured_project_limit_minutes - item.accepted_project_minutes,
            0,
        )
        if item.remaining_project_capacity_minutes != expected_remaining:
            raise SolverInputError("daily capacity remaining minutes are inconsistent")
        expected_usable = min(item.calendar_free_minutes, expected_remaining)
        if item.usable_project_minutes != expected_usable:
            raise SolverInputError("daily capacity usable minutes are inconsistent")


def _candidate_assumptions(workload: WorkloadAnalysis) -> tuple[str, ...]:
    required = set(workload.required_task_ids)
    result = ["solver effort basis: LIKELY"]
    for assumption in workload.assumptions:
        if assumption.task_id is not None and assumption.task_id not in required:
            continue
        if assumption.task_id is None:
            result.append(assumption.description)
        else:
            result.append(f"{assumption.task_id}: {assumption.description}")
    return tuple(sorted(set(result)))


def _sum_effort(tasks) -> EffortRange:
    return EffortRange(
        min_minutes=sum(task.effort_min_minutes for task in tasks),
        likely_minutes=sum(task.effort_likely_minutes for task in tasks),
        max_minutes=sum(task.effort_max_minutes for task in tasks),
    )
