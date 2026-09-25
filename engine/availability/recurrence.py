"""Strict MVP recurrence parsing and expansion for availability."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo

from packages.contracts.planning import (
    PlanningCommitment,
    RecurrenceExceptionAction,
    RecurrenceSpec,
)


class RecurrenceError(ValueError):
    """Base recurrence correctness error."""


class UnsupportedRecurrenceRuleError(RecurrenceError):
    """Raised when an RRULE uses syntax outside the frozen MVP subset."""


class InvalidRecurrenceExceptionError(RecurrenceError):
    """Raised when an exception does not target exactly one real occurrence."""


class InvalidLocalTimeError(RecurrenceError):
    """Raised for nonexistent or ambiguous recurrence wall-clock times."""


@dataclass(frozen=True, slots=True)
class ParsedRRule:
    frequency: str
    interval: int
    by_weekday: tuple[int, ...]


_WEEKDAY = {
    "MO": 0,
    "TU": 1,
    "WE": 2,
    "TH": 3,
    "FR": 4,
    "SA": 5,
    "SU": 6,
}
_ALLOWED_KEYS = frozenset({"FREQ", "INTERVAL", "BYDAY"})


def parse_rrule(spec: RecurrenceSpec) -> ParsedRRule:
    parts: dict[str, str] = {}
    for fragment in spec.rrule.split(";"):
        if not fragment or "=" not in fragment:
            raise UnsupportedRecurrenceRuleError("RRULE fragments must use KEY=VALUE syntax")
        key, value = fragment.split("=", 1)
        key = key.strip().upper()
        value = value.strip().upper()
        if key in parts:
            raise UnsupportedRecurrenceRuleError(f"duplicate RRULE key: {key}")
        if key not in _ALLOWED_KEYS:
            raise UnsupportedRecurrenceRuleError(f"unsupported RRULE key: {key}")
        if not value:
            raise UnsupportedRecurrenceRuleError(f"RRULE {key} must not be empty")
        parts[key] = value

    frequency = parts.get("FREQ")
    if frequency not in {"DAILY", "WEEKLY"}:
        raise UnsupportedRecurrenceRuleError("FREQ must be DAILY or WEEKLY")

    interval_text = parts.get("INTERVAL", "1")
    if not interval_text.isdecimal() or int(interval_text) < 1:
        raise UnsupportedRecurrenceRuleError("INTERVAL must be a positive integer")
    interval = int(interval_text)

    by_weekday: tuple[int, ...] = ()
    if "BYDAY" in parts:
        tokens = parts["BYDAY"].split(",")
        if any(token not in _WEEKDAY for token in tokens):
            raise UnsupportedRecurrenceRuleError("BYDAY only supports MO,TU,WE,TH,FR,SA,SU")
        values = tuple(_WEEKDAY[token] for token in tokens)
        if len(set(values)) != len(values):
            raise UnsupportedRecurrenceRuleError("BYDAY must not contain duplicates")
        by_weekday = tuple(sorted(values))

    return ParsedRRule(frequency=frequency, interval=interval, by_weekday=by_weekday)


def expand_commitment(
    commitment: PlanningCommitment,
    horizon_start: datetime,
    horizon_end: datetime,
) -> list[tuple[datetime, datetime]]:
    if commitment.recurrence is None:
        return [(commitment.start_at, commitment.end_at)]

    parsed = parse_rrule(commitment.recurrence)
    zone = ZoneInfo(commitment.timezone)
    anchor_start = commitment.start_at.astimezone(zone)
    anchor_end = commitment.end_at.astimezone(zone)

    _validate_exception_targets(commitment, parsed, zone, anchor_start, anchor_end)
    exception_map = {
        item.original_start_at.astimezone(UTC): item for item in commitment.exceptions
    }

    local_horizon_start = horizon_start.astimezone(zone)
    local_horizon_end = horizon_end.astimezone(zone)
    day_span = max(0, (anchor_end.date() - anchor_start.date()).days)
    scan_date = local_horizon_start.date() - timedelta(days=day_span + 1)
    final_date = local_horizon_end.date()

    occurrences: list[tuple[datetime, datetime]] = []
    while scan_date <= final_date:
        pair = _occurrence_for_date(
            commitment.recurrence,
            parsed,
            scan_date,
            anchor_start,
            anchor_end,
            zone,
        )
        if pair is not None:
            start, end = pair
            exception = exception_map.get(start.astimezone(UTC))
            if exception is None:
                if _overlaps(start, end, horizon_start, horizon_end):
                    occurrences.append((start, end))
            elif exception.action is RecurrenceExceptionAction.MOVED:
                assert exception.replacement_start_at is not None
                assert exception.replacement_end_at is not None
                if _overlaps(
                    exception.replacement_start_at,
                    exception.replacement_end_at,
                    horizon_start,
                    horizon_end,
                ):
                    occurrences.append(
                        (exception.replacement_start_at, exception.replacement_end_at)
                    )
        scan_date += timedelta(days=1)

    # A MOVED occurrence can originate outside the current horizon and land inside it.
    generated_originals = {
        start.astimezone(UTC)
        for start, _ in _series_occurrences_for_exception_targets(
            commitment,
            parsed,
            zone,
            anchor_start,
            anchor_end,
        )
    }
    for exception in commitment.exceptions:
        if exception.action is not RecurrenceExceptionAction.MOVED:
            continue
        original_utc = exception.original_start_at.astimezone(UTC)
        if original_utc not in generated_originals:
            # Defensive; _validate_exception_targets should already prevent this.
            raise InvalidRecurrenceExceptionError(
                "MOVED exception does not target a real recurrence occurrence"
            )
        assert exception.replacement_start_at is not None
        assert exception.replacement_end_at is not None
        original_in_horizon = _overlaps(
            exception.original_start_at,
            _original_end_for_exception(
                commitment,
                parsed,
                zone,
                anchor_start,
                anchor_end,
                exception.original_start_at,
            ),
            horizon_start,
            horizon_end,
        )
        replacement_in_horizon = _overlaps(
            exception.replacement_start_at,
            exception.replacement_end_at,
            horizon_start,
            horizon_end,
        )
        if replacement_in_horizon and not original_in_horizon:
            occurrences.append((exception.replacement_start_at, exception.replacement_end_at))

    occurrences.sort(key=lambda pair: (pair[0].astimezone(UTC), pair[1].astimezone(UTC)))
    return occurrences


def _series_occurrences_for_exception_targets(
    commitment: PlanningCommitment,
    parsed: ParsedRRule,
    zone: ZoneInfo,
    anchor_start: datetime,
    anchor_end: datetime,
) -> list[tuple[datetime, datetime]]:
    result: list[tuple[datetime, datetime]] = []
    target_dates = {
        item.original_start_at.astimezone(zone).date() for item in commitment.exceptions
    }
    for target_date in sorted(target_dates):
        pair = _occurrence_for_date(
            commitment.recurrence,
            parsed,
            target_date,
            anchor_start,
            anchor_end,
            zone,
        )
        if pair is not None:
            result.append(pair)
    return result


def _validate_exception_targets(
    commitment: PlanningCommitment,
    parsed: ParsedRRule,
    zone: ZoneInfo,
    anchor_start: datetime,
    anchor_end: datetime,
) -> None:
    for exception in commitment.exceptions:
        target_local = exception.original_start_at.astimezone(zone)
        pair = _occurrence_for_date(
            commitment.recurrence,
            parsed,
            target_local.date(),
            anchor_start,
            anchor_end,
            zone,
        )
        if pair is None or pair[0].astimezone(UTC) != exception.original_start_at.astimezone(UTC):
            raise InvalidRecurrenceExceptionError(
                "recurrence exception must match exactly one generated original occurrence"
            )


def _original_end_for_exception(
    commitment: PlanningCommitment,
    parsed: ParsedRRule,
    zone: ZoneInfo,
    anchor_start: datetime,
    anchor_end: datetime,
    original_start: datetime,
) -> datetime:
    pair = _occurrence_for_date(
        commitment.recurrence,
        parsed,
        original_start.astimezone(zone).date(),
        anchor_start,
        anchor_end,
        zone,
    )
    if pair is None:
        raise InvalidRecurrenceExceptionError("exception original occurrence is invalid")
    return pair[1]


def _occurrence_for_date(
    spec: RecurrenceSpec | None,
    parsed: ParsedRRule,
    current: date,
    anchor_start: datetime,
    anchor_end: datetime,
    zone: ZoneInfo,
) -> tuple[datetime, datetime] | None:
    assert spec is not None
    if not _date_matches(current, anchor_start.date(), anchor_start.weekday(), parsed):
        return None

    day_span = (anchor_end.date() - anchor_start.date()).days
    start_naive = datetime.combine(current, anchor_start.time().replace(tzinfo=None))
    end_date = current + timedelta(days=day_span)
    end_naive = datetime.combine(end_date, anchor_end.time().replace(tzinfo=None))

    start = _localize_strict(start_naive, zone)
    end = _localize_strict(end_naive, zone)
    if end.astimezone(UTC) <= start.astimezone(UTC):
        # Preserve an explicitly cross-midnight source event.
        end = _localize_strict(end_naive + timedelta(days=1), zone)

    if start.astimezone(UTC) < anchor_start.astimezone(UTC):
        return None
    if start.astimezone(UTC) < spec.active_from.astimezone(UTC):
        return None
    if spec.active_until is not None and start.astimezone(UTC) >= spec.active_until.astimezone(UTC):
        return None
    return start, end


def _date_matches(
    current: date,
    anchor: date,
    anchor_weekday: int,
    parsed: ParsedRRule,
) -> bool:
    delta_days = (current - anchor).days
    if delta_days < 0:
        return False

    weekdays = parsed.by_weekday
    if parsed.frequency == "DAILY":
        if delta_days % parsed.interval != 0:
            return False
        return not weekdays or current.weekday() in weekdays

    # Freeze WKST=MO for the MVP subset. Weekly INTERVAL is measured in
    # Monday-based week buckets, not integer division from DTSTART's weekday.
    anchor_week_start = anchor - timedelta(days=anchor.weekday())
    current_week_start = current - timedelta(days=current.weekday())
    weeks_since_anchor = (current_week_start - anchor_week_start).days // 7
    if weeks_since_anchor < 0 or weeks_since_anchor % parsed.interval != 0:
        return False
    allowed = weekdays or (anchor_weekday,)
    return current.weekday() in allowed


def _localize_strict(local_naive: datetime, zone: ZoneInfo) -> datetime:
    candidates: dict[datetime, datetime] = {}
    for fold in (0, 1):
        aware = local_naive.replace(tzinfo=zone, fold=fold)
        roundtrip = aware.astimezone(UTC).astimezone(zone)
        if roundtrip.replace(tzinfo=None) != local_naive:
            continue
        candidates[aware.astimezone(UTC)] = aware

    if not candidates:
        raise InvalidLocalTimeError(
            f"nonexistent local recurrence time {local_naive.isoformat()} in {zone.key}"
        )
    if len(candidates) > 1:
        raise InvalidLocalTimeError(
            f"ambiguous local recurrence time {local_naive.isoformat()} in {zone.key}"
        )
    return next(iter(candidates.values()))


def _overlaps(start: datetime, end: datetime, lower: datetime, upper: datetime) -> bool:
    start_utc = start.astimezone(UTC)
    end_utc = end.astimezone(UTC)
    lower_utc = lower.astimezone(UTC)
    upper_utc = upper.astimezone(UTC)
    return end_utc > lower_utc and start_utc < upper_utc
