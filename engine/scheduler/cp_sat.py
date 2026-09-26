"""OR-Tools CP-SAT candidate allocation model for Issue 3A Block 3."""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from engine.availability.models import AvailabilityResult
from engine.scheduler.models import SolverConfig, SolverRunStatus
from packages.contracts.models import AllocationBlock
from packages.contracts.workload import WorkloadAnalysis


class SolverDependencyUnavailableError(RuntimeError):
    """Raised when OR-Tools is not installed in the current runtime."""


@dataclass(frozen=True, slots=True)
class RawSolverSolution:
    status: SolverRunStatus
    work_blocks: tuple[AllocationBlock, ...]
    used_window_ids: tuple[str, ...] = ()
    makespan_minutes: int | None = None


@dataclass(frozen=True, slots=True)
class _Window:
    window_id: str
    start_offset: int
    end_offset: int
    local_date: date
    source: str

    @property
    def length(self) -> int:
        return self.end_offset - self.start_offset


@dataclass(slots=True)
class _FragmentVars:
    task_id: str
    window: _Window
    start: object
    duration: object
    end: object
    present: object


def solve_cp_sat(
    availability: AvailabilityResult,
    workload: WorkloadAnalysis,
    config: SolverConfig,
    *,
    materially_distinct_from: tuple[RawSolverSolution, ...] = (),
) -> RawSolverSolution:
    """Solve one deterministic required-task candidate using likely effort."""

    try:
        from ortools.sat.python import cp_model
    except ModuleNotFoundError as exc:
        raise SolverDependencyUnavailableError(
            "OR-Tools is required for Block 3 CP-SAT execution"
        ) from exc

    zone = ZoneInfo(availability.timezone)
    base_utc = availability.horizon_start.astimezone(UTC)
    deadline_utc = config.submission_deadline.astimezone(UTC)
    horizon_end_utc = availability.horizon_end.astimezone(UTC)
    effective_end_utc = min(deadline_utc, horizon_end_utc)
    if effective_end_utc <= base_utc:
        return RawSolverSolution(SolverRunStatus.INFEASIBLE, ())

    horizon_minutes = _minute_offset(base_utc, effective_end_utc)
    windows = _solver_windows(availability, base_utc, effective_end_utc, zone)
    task_by_id = {task.task_id: task for task in workload.tasks}
    required_ids = tuple(workload.required_task_ids)
    positive_ids = tuple(
        task_id
        for task_id in required_ids
        if task_by_id[task_id].effort_likely_minutes > 0
    )

    if positive_ids and not windows:
        return RawSolverSolution(SolverRunStatus.INFEASIBLE, ())

    model = cp_model.CpModel()
    fragments: dict[str, list[_FragmentVars]] = defaultdict(list)
    intervals_by_window: dict[str, list[object]] = defaultdict(list)
    presence_by_window: dict[str, list[object]] = defaultdict(list)
    daily_durations: dict[date, list[object]] = defaultdict(list)
    all_presence: list[object] = []

    for task_id in positive_ids:
        task = task_by_id[task_id]
        for window in windows:
            start = model.NewIntVar(
                window.start_offset,
                window.end_offset,
                f"start_{task_id}_{window.window_id}",
            )
            duration = model.NewIntVar(
                0,
                window.length,
                f"duration_{task_id}_{window.window_id}",
            )
            end = model.NewIntVar(
                window.start_offset,
                window.end_offset,
                f"end_{task_id}_{window.window_id}",
            )
            present = model.NewBoolVar(f"present_{task_id}_{window.window_id}")
            interval = model.NewOptionalIntervalVar(
                start,
                duration,
                end,
                present,
                f"interval_{task_id}_{window.window_id}",
            )
            model.Add(duration == 0).OnlyEnforceIf(present.Not())
            model.Add(duration >= 1).OnlyEnforceIf(present)
            model.Add(end <= window.end_offset)
            fragments[task_id].append(
                _FragmentVars(task_id, window, start, duration, end, present)
            )
            intervals_by_window[window.window_id].append(interval)
            presence_by_window[window.window_id].append(present)
            daily_durations[window.local_date].append(duration)
            all_presence.append(present)

        model.Add(
            sum(fragment.duration for fragment in fragments[task_id])
            == task.effort_likely_minutes
        )

    for intervals in intervals_by_window.values():
        model.AddNoOverlap(intervals)

    window_used: dict[str, object] = {}
    for window in windows:
        used = model.NewBoolVar(f"used_{window.window_id}")
        presences = presence_by_window[window.window_id]
        if presences:
            model.Add(sum(presences) >= 1).OnlyEnforceIf(used)
            model.Add(sum(presences) == 0).OnlyEnforceIf(used.Not())
        else:
            model.Add(used == 0)
        window_used[window.window_id] = used

    daily_limits = _effective_daily_limits(availability, windows)
    for local_date, durations in daily_durations.items():
        model.Add(sum(durations) <= daily_limits.get(local_date, 0))

    task_start: dict[str, object] = {}
    task_end: dict[str, object] = {}
    for task_id in positive_ids:
        starts: list[object] = []
        ends: list[object] = []
        for index, fragment in enumerate(fragments[task_id]):
            effective_start = model.NewIntVar(
                0,
                horizon_minutes,
                f"effective_start_{task_id}_{index}",
            )
            effective_end = model.NewIntVar(
                0,
                horizon_minutes,
                f"effective_end_{task_id}_{index}",
            )
            model.Add(effective_start == fragment.start).OnlyEnforceIf(fragment.present)
            model.Add(effective_start == horizon_minutes).OnlyEnforceIf(
                fragment.present.Not()
            )
            model.Add(effective_end == fragment.end).OnlyEnforceIf(fragment.present)
            model.Add(effective_end == 0).OnlyEnforceIf(fragment.present.Not())
            starts.append(effective_start)
            ends.append(effective_end)

        start_var = model.NewIntVar(0, horizon_minutes, f"task_start_{task_id}")
        end_var = model.NewIntVar(0, horizon_minutes, f"task_end_{task_id}")
        model.AddMinEquality(start_var, starts)
        model.AddMaxEquality(end_var, ends)
        task_start[task_id] = start_var
        task_end[task_id] = end_var

    for task_id in required_ids:
        task = task_by_id[task_id]
        if task.effort_likely_minutes == 0:
            milestone = model.NewIntVar(0, horizon_minutes, f"milestone_{task_id}")
            task_start[task_id] = milestone
            task_end[task_id] = milestone

    for task_id in required_ids:
        task = task_by_id[task_id]
        if task.effort_likely_minutes == 0:
            dependency_ends = [task_end[item] for item in task.dependencies]
            if dependency_ends:
                model.AddMaxEquality(task_start[task_id], dependency_ends)
            else:
                model.Add(task_start[task_id] == 0)
        for dependency in task.dependencies:
            model.Add(task_start[task_id] >= task_end[dependency])

    required_effort = sum(
        task_by_id[task_id].effort_likely_minutes for task_id in required_ids
    )
    total_capacity = sum(daily_limits.values())
    if required_effort + config.buffer_target_minutes > total_capacity:
        return RawSolverSolution(SolverRunStatus.INFEASIBLE, ())

    positive_end_vars = [task_end[task_id] for task_id in positive_ids]
    makespan = None
    if positive_end_vars:
        makespan = model.NewIntVar(0, horizon_minutes, "makespan")
        model.AddMaxEquality(makespan, positive_end_vars)

    _add_material_difference_constraints(
        model,
        window_used,
        makespan,
        horizon_minutes,
        materially_distinct_from,
    )

    if makespan is not None:
        weight = horizon_minutes + 1
        model.Minimize(sum(all_presence) * weight + makespan)

    solver = cp_model.CpSolver()
    solver.parameters.num_search_workers = 1
    solver.parameters.random_seed = 0
    solver.parameters.max_deterministic_time = 10.0
    status = solver.Solve(model)

    mapped_status = _map_status(status, cp_model)
    if mapped_status not in {SolverRunStatus.OPTIMAL, SolverRunStatus.FEASIBLE}:
        return RawSolverSolution(mapped_status, ())

    work_blocks: list[AllocationBlock] = []
    used_window_ids: set[str] = set()
    for task_id in positive_ids:
        for fragment in fragments[task_id]:
            if not solver.BooleanValue(fragment.present):
                continue
            start_offset = solver.Value(fragment.start)
            duration = solver.Value(fragment.duration)
            if duration <= 0:
                continue
            used_window_ids.add(fragment.window.window_id)
            end_offset = start_offset + duration
            start_utc = base_utc + timedelta(minutes=start_offset)
            end_utc = base_utc + timedelta(minutes=end_offset)
            work_blocks.append(
                AllocationBlock(
                    task_id=task_id,
                    start=start_utc.astimezone(zone),
                    end=end_utc.astimezone(zone),
                    allocated_minutes=duration,
                    availability_source=fragment.window.source,
                )
            )

    ordered = tuple(
        sorted(
            work_blocks,
            key=lambda item: (item.start.astimezone(UTC), item.task_id),
        )
    )
    makespan_minutes = solver.Value(makespan) if makespan is not None else None
    return RawSolverSolution(
        mapped_status,
        ordered,
        tuple(sorted(used_window_ids)),
        makespan_minutes,
    )


_MATERIAL_COMPLETION_DELTA_MINUTES = 30


def _add_material_difference_constraints(
    model,
    window_used: dict[str, object],
    makespan,
    horizon_minutes: int,
    previous_solutions: tuple[RawSolverSolution, ...],
) -> None:
    for index, previous in enumerate(previous_solutions):
        literals = []
        previous_windows = set(previous.used_window_ids)
        for window_id, used in sorted(window_used.items()):
            literals.append(
                used.Not() if window_id in previous_windows else used
            )

        if makespan is not None and previous.makespan_minutes is not None:
            earlier_limit = (
                previous.makespan_minutes - _MATERIAL_COMPLETION_DELTA_MINUTES
            )
            if earlier_limit >= 0:
                earlier = model.NewBoolVar(f"material_earlier_{index}")
                model.Add(makespan <= earlier_limit).OnlyEnforceIf(earlier)
                literals.append(earlier)

            later_limit = (
                previous.makespan_minutes + _MATERIAL_COMPLETION_DELTA_MINUTES
            )
            if later_limit <= horizon_minutes:
                later = model.NewBoolVar(f"material_later_{index}")
                model.Add(makespan >= later_limit).OnlyEnforceIf(later)
                literals.append(later)

        model.AddBoolOr(literals)


def _solver_windows(
    availability: AvailabilityResult,
    base_utc: datetime,
    effective_end_utc: datetime,
    zone: ZoneInfo,
) -> tuple[_Window, ...]:
    windows: list[_Window] = []
    index = 0
    ordered_blocks = sorted(
        availability.available_blocks,
        key=lambda block: (
            block.start.astimezone(UTC),
            block.end.astimezone(UTC),
            block.source,
        ),
    )
    for block in ordered_blocks:
        start_utc = max(block.start.astimezone(UTC), base_utc)
        end_utc = min(block.end.astimezone(UTC), effective_end_utc)
        if end_utc <= start_utc:
            continue
        current_date = start_utc.astimezone(zone).date()
        final_date = (end_utc - timedelta(microseconds=1)).astimezone(zone).date()
        while current_date <= final_date:
            day_start = datetime.combine(current_date, time.min, tzinfo=zone)
            day_end = datetime.combine(
                current_date + timedelta(days=1),
                time.min,
                tzinfo=zone,
            )
            lower = max(start_utc, day_start.astimezone(UTC))
            upper = min(end_utc, day_end.astimezone(UTC))
            if upper > lower:
                windows.append(
                    _Window(
                        window_id=f"w{index}",
                        start_offset=_minute_offset(base_utc, lower),
                        end_offset=_minute_offset(base_utc, upper),
                        local_date=current_date,
                        source=block.source,
                    )
                )
                index += 1
            current_date += timedelta(days=1)
    return tuple(sorted(windows, key=lambda item: (item.start_offset, item.window_id)))


def _effective_daily_limits(
    availability: AvailabilityResult,
    windows: tuple[_Window, ...],
) -> dict[date, int]:
    available_minutes: dict[date, int] = defaultdict(int)
    for window in windows:
        available_minutes[window.local_date] += window.length
    return {
        item.local_date: min(
            item.usable_project_minutes,
            available_minutes[item.local_date],
        )
        for item in availability.daily_capacity
    }


def _minute_offset(base_utc: datetime, value_utc: datetime) -> int:
    seconds = (value_utc - base_utc).total_seconds()
    return int(seconds // 60)


def _map_status(status: int, cp_model) -> SolverRunStatus:
    if status == cp_model.OPTIMAL:
        return SolverRunStatus.OPTIMAL
    if status == cp_model.FEASIBLE:
        return SolverRunStatus.FEASIBLE
    if status == cp_model.INFEASIBLE:
        return SolverRunStatus.INFEASIBLE
    return SolverRunStatus.UNKNOWN
