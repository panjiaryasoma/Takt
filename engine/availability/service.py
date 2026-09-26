"""Deterministic availability derivation for Issue 3A Block 1.

All interval algebra is performed on UTC instants. Local timezone values are
used only for recurrence interpretation, local calendar-day accounting, and
output projection. This avoids Python's same-ZoneInfo wall-time comparison
behavior across DST folds.
"""

from __future__ import annotations

from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from engine.availability.models import AvailabilityResult, DailyCapacity
from engine.availability.recurrence import expand_commitment
from packages.contracts import AvailabilityBlock, AvailabilityType, CommitmentType
from packages.contracts.planning import AvailabilityInput


@dataclass(frozen=True, slots=True)
class _BusyInterval:
    start: datetime  # UTC instant
    end: datetime  # UTC instant
    availability_type: AvailabilityType
    sources: tuple[str, ...]


_PRECEDENCE = {
    AvailabilityType.FLEXIBLE_BUSY: 1,
    AvailabilityType.FIXED_BUSY: 2,
    AvailabilityType.ACCEPTED_PROJECT_COMMITMENT: 3,
}


def build_availability(data: AvailabilityInput) -> AvailabilityResult:
    """Derive typed busy blocks and raw AVAILABLE blocks inside work windows.

    Daily project limits are surfaced as capacity metadata. They do not truncate
    raw AVAILABLE time; CP-SAT enforces allocation capacity later.
    """

    # Revalidate at the decision boundary so model_construct/object hacks cannot
    # silently alter semantics after initial construction.
    data = AvailabilityInput.model_validate(data.model_dump(mode="python"))

    zone = ZoneInfo(data.preferences.timezone)
    horizon_start_utc = _utc(data.horizon.start)
    horizon_end_utc = _utc(data.horizon.end)

    raw_busy = _build_raw_busy(data, horizon_start_utc, horizon_end_utc)
    normalized_busy = _normalize_busy(raw_busy)
    busy_blocks = [_project_busy(block, zone) for block in normalized_busy]

    work_windows = _normalized_work_windows(data, horizon_start_utc, horizon_end_utc)
    available_utc = _derive_available_intervals(normalized_busy, work_windows)
    available_blocks = [
        _available_block(start, end, zone, index)
        for index, (start, end) in enumerate(available_utc)
    ]

    free_minutes = _minutes_by_calendar_day(
        available_utc,
        zone,
        horizon_start_utc,
        horizon_end_utc,
    )
    accepted_minutes = _accepted_minutes_by_calendar_day(
        data,
        zone,
        horizon_start_utc,
        horizon_end_utc,
    )
    daily_capacity = _build_daily_capacity(
        free_minutes,
        accepted_minutes,
        data.preferences.max_project_minutes_per_day,
        zone,
        horizon_start_utc,
        horizon_end_utc,
    )

    return AvailabilityResult(
        timezone=data.preferences.timezone,
        horizon_start=horizon_start_utc.astimezone(zone),
        horizon_end=horizon_end_utc.astimezone(zone),
        busy_blocks=tuple(busy_blocks),
        available_blocks=tuple(available_blocks),
        daily_capacity=tuple(daily_capacity),
    )


def _build_raw_busy(
    data: AvailabilityInput,
    horizon_start_utc: datetime,
    horizon_end_utc: datetime,
) -> list[_BusyInterval]:
    result: list[_BusyInterval] = []
    for commitment in data.commitments:
        availability_type = (
            AvailabilityType.FIXED_BUSY
            if commitment.type is CommitmentType.FIXED
            else AvailabilityType.FLEXIBLE_BUSY
        )
        source = f"{commitment.source}:{commitment.commitment_id}"
        for start, end in expand_commitment(
            commitment,
            horizon_start_utc,
            horizon_end_utc,
        ):
            clipped = _clip(
                _utc(start),
                _utc(end),
                horizon_start_utc,
                horizon_end_utc,
            )
            if clipped is not None:
                result.append(
                    _BusyInterval(
                        start=clipped[0],
                        end=clipped[1],
                        availability_type=availability_type,
                        sources=(source,),
                    )
                )

    for commitment in data.accepted_commitments:
        clipped = _clip(
            _utc(commitment.start_at),
            _utc(commitment.end_at),
            horizon_start_utc,
            horizon_end_utc,
        )
        if clipped is None:
            continue
        result.append(
            _BusyInterval(
                start=clipped[0],
                end=clipped[1],
                availability_type=AvailabilityType.ACCEPTED_PROJECT_COMMITMENT,
                sources=(f"{commitment.source}:{commitment.accepted_commitment_id}",),
            )
        )

    return result


def _normalize_busy(intervals: list[_BusyInterval]) -> list[_BusyInterval]:
    """Sweep-line normalization with deterministic precedence and provenance.

    Sorting events is O(n log n). Each boundary updates only intervals starting
    or ending there, rather than rescanning all intervals. Serializing source
    provenance is proportional to the number of currently active sources.
    """

    if not intervals:
        return []

    starts: dict[datetime, list[int]] = defaultdict(list)
    ends: dict[datetime, list[int]] = defaultdict(list)
    for index, item in enumerate(intervals):
        starts[item.start].append(index)
        ends[item.end].append(index)

    boundaries = sorted(set(starts) | set(ends))
    active_ids: set[int] = set()
    type_counts: Counter[AvailabilityType] = Counter()
    source_counts: Counter[str] = Counter()
    segments: list[_BusyInterval] = []
    previous: datetime | None = None

    for point in boundaries:
        if previous is not None and previous < point and active_ids:
            winner_type = _winning_type(type_counts)
            sources = tuple(sorted(source_counts))
            segment = _BusyInterval(previous, point, winner_type, sources)
            _append_or_merge_segment(segments, segment)

        # Half-open [start, end): intervals ending at point are inactive after
        # this boundary; intervals starting at point are active after it.
        for index in ends.get(point, ()):
            if index not in active_ids:
                continue
            item = intervals[index]
            active_ids.remove(index)
            _counter_remove(type_counts, item.availability_type)
            for source in item.sources:
                _counter_remove(source_counts, source)

        for index in starts.get(point, ()):
            item = intervals[index]
            active_ids.add(index)
            type_counts[item.availability_type] += 1
            for source in item.sources:
                source_counts[source] += 1

        previous = point

    return segments


def _winning_type(counts: Counter[AvailabilityType]) -> AvailabilityType:
    return max(
        (kind for kind, count in counts.items() if count > 0),
        key=lambda kind: _PRECEDENCE[kind],
    )


def _counter_remove(counter: Counter, key) -> None:
    counter[key] -= 1
    if counter[key] <= 0:
        del counter[key]


def _append_or_merge_segment(
    segments: list[_BusyInterval],
    segment: _BusyInterval,
) -> None:
    if (
        segments
        and segments[-1].end == segment.start
        and segments[-1].availability_type is segment.availability_type
        and segments[-1].sources == segment.sources
    ):
        previous = segments[-1]
        segments[-1] = _BusyInterval(
            previous.start,
            segment.end,
            previous.availability_type,
            previous.sources,
        )
        return
    segments.append(segment)


def _normalized_work_windows(
    data: AvailabilityInput,
    horizon_start_utc: datetime,
    horizon_end_utc: datetime,
) -> list[tuple[datetime, datetime]]:
    clipped: list[tuple[datetime, datetime]] = []
    for window in data.work_windows:
        candidate = _clip(
            _utc(window.start),
            _utc(window.end),
            horizon_start_utc,
            horizon_end_utc,
        )
        if candidate is not None:
            clipped.append(candidate)
    return _merge_intervals(clipped)


def _derive_available_intervals(
    busy: list[_BusyInterval],
    work_windows: list[tuple[datetime, datetime]],
) -> list[tuple[datetime, datetime]]:
    result: list[tuple[datetime, datetime]] = []
    busy_union = _merge_intervals((item.start, item.end) for item in busy)
    busy_index = 0

    for window_start, window_end in work_windows:
        while busy_index < len(busy_union) and busy_union[busy_index][1] <= window_start:
            busy_index += 1

        cursor = window_start
        index = busy_index
        while index < len(busy_union):
            busy_start, busy_end = busy_union[index]
            if busy_start >= window_end:
                break
            clipped_start = max(busy_start, window_start)
            clipped_end = min(busy_end, window_end)
            if clipped_start > cursor:
                result.append((cursor, clipped_start))
            cursor = max(cursor, clipped_end)
            if cursor >= window_end:
                break
            index += 1

        if cursor < window_end:
            result.append((cursor, window_end))

    return result


def _accepted_minutes_by_calendar_day(
    data: AvailabilityInput,
    zone: ZoneInfo,
    horizon_start_utc: datetime,
    horizon_end_utc: datetime,
) -> dict[date, int]:
    intervals: list[tuple[datetime, datetime]] = []
    for item in data.accepted_commitments:
        clipped = _clip(
            _utc(item.start_at),
            _utc(item.end_at),
            horizon_start_utc,
            horizon_end_utc,
        )
        if clipped is not None:
            intervals.append(clipped)
    return _minutes_by_calendar_day(
        _merge_intervals(intervals),
        zone,
        horizon_start_utc,
        horizon_end_utc,
    )


def _minutes_by_calendar_day(
    intervals,
    zone: ZoneInfo,
    horizon_start_utc: datetime,
    horizon_end_utc: datetime,
) -> dict[date, int]:
    """Count elapsed minutes by local calendar date using UTC intersections."""

    merged = _merge_intervals(intervals)
    result: dict[date, int] = {}
    for local_date in _dates_in_horizon(horizon_start_utc, horizon_end_utc, zone):
        day_start_local = datetime.combine(local_date, time.min, tzinfo=zone)
        next_day_local = datetime.combine(
            local_date + timedelta(days=1),
            time.min,
            tzinfo=zone,
        )
        day_start_utc = day_start_local.astimezone(UTC)
        day_end_utc = next_day_local.astimezone(UTC)
        total = 0
        for start, end in merged:
            if end <= day_start_utc:
                continue
            if start >= day_end_utc:
                break
            clipped = _clip(start, end, day_start_utc, day_end_utc)
            if clipped is not None:
                total += _minutes(*clipped)
        if total:
            result[local_date] = total
    return result


def _build_daily_capacity(
    free_minutes: dict[date, int],
    accepted_minutes: dict[date, int],
    configured_limit: int,
    zone: ZoneInfo,
    horizon_start_utc: datetime,
    horizon_end_utc: datetime,
) -> list[DailyCapacity]:
    result: list[DailyCapacity] = []
    for local_date in _dates_in_horizon(horizon_start_utc, horizon_end_utc, zone):
        free = free_minutes.get(local_date, 0)
        accepted = accepted_minutes.get(local_date, 0)
        remaining = max(0, configured_limit - accepted)
        result.append(
            DailyCapacity(
                local_date=local_date,
                calendar_free_minutes=free,
                accepted_project_minutes=accepted,
                configured_project_limit_minutes=configured_limit,
                remaining_project_capacity_minutes=remaining,
                usable_project_minutes=min(free, remaining),
            )
        )
    return result


def _project_busy(item: _BusyInterval, zone: ZoneInfo) -> AvailabilityBlock:
    return AvailabilityBlock(
        start=item.start.astimezone(zone),
        end=item.end.astimezone(zone),
        timezone=zone.key,
        source="|".join(item.sources),
        availability_type=item.availability_type,
    )


def _available_block(
    start_utc: datetime,
    end_utc: datetime,
    zone: ZoneInfo,
    index: int,
) -> AvailabilityBlock:
    return AvailabilityBlock(
        start=start_utc.astimezone(zone),
        end=end_utc.astimezone(zone),
        timezone=zone.key,
        source=f"derived:work_window:{index}",
        availability_type=AvailabilityType.AVAILABLE,
    )


def _merge_intervals(intervals) -> list[tuple[datetime, datetime]]:
    ordered = sorted(
        (start, end)
        for start, end in intervals
        if end > start
    )
    if not ordered:
        return []
    result = [ordered[0]]
    for start, end in ordered[1:]:
        previous_start, previous_end = result[-1]
        if start <= previous_end:
            result[-1] = previous_start, max(previous_end, end)
        else:
            result.append((start, end))
    return result


def _dates_in_horizon(
    horizon_start_utc: datetime,
    horizon_end_utc: datetime,
    zone: ZoneInfo,
):
    current = horizon_start_utc.astimezone(zone).date()
    final = (horizon_end_utc - timedelta(microseconds=1)).astimezone(zone).date()
    while current <= final:
        yield current
        current += timedelta(days=1)


def _clip(
    start_utc: datetime,
    end_utc: datetime,
    lower_utc: datetime,
    upper_utc: datetime,
) -> tuple[datetime, datetime] | None:
    clipped_start = max(start_utc, lower_utc)
    clipped_end = min(end_utc, upper_utc)
    if clipped_end <= clipped_start:
        return None
    return clipped_start, clipped_end


def _minutes(start_utc: datetime, end_utc: datetime) -> int:
    seconds = (end_utc - start_utc).total_seconds()
    if seconds % 60 != 0:
        raise ValueError("availability intervals must remain minute-aligned")
    return int(seconds // 60)


def _utc(value: datetime) -> datetime:
    return value.astimezone(UTC)
