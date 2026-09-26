"""Planning contracts for Issue 3A availability.

The pre-production documents require explicit work windows, timezone-preserving
recurrence semantics, max project capacity, focus preference, and buffer target.

The numeric horizon cap below is an implementation safety proposal because the
pre-production source of truth does not define a concrete maximum horizon.
"""

from __future__ import annotations

from datetime import UTC, datetime
from enum import StrEnum
from typing import Annotated
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    StrictInt,
    StringConstraints,
    model_validator,
)

from packages.contracts.enums import CommitmentType

NonEmptyStr = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, strict=True),
]

# Implementation safety policy proposal. Pre-production requires a bounded
# evaluation horizon but does not freeze a numeric limit.
MAX_PLANNING_HORIZON_DAYS = 366


class PlanningContract(BaseModel):
    """Strict/frozen boundary model for planning inputs."""

    model_config = ConfigDict(extra="forbid", frozen=True, validate_default=True)


class RecurrenceExceptionAction(StrEnum):
    CANCELLED = "CANCELLED"
    MOVED = "MOVED"


class PlanningHorizon(PlanningContract):
    start: AwareDatetime
    end: AwareDatetime

    @model_validator(mode="after")
    def validate_horizon(self) -> PlanningHorizon:
        _require_minute_aligned(self.start, "horizon.start")
        _require_minute_aligned(self.end, "horizon.end")
        if not _instant_before(self.start, self.end):
            raise ValueError("planning horizon end must be after start by instant")
        elapsed = (_as_utc(self.end) - _as_utc(self.start)).total_seconds()
        if elapsed > MAX_PLANNING_HORIZON_DAYS * 86400:
            raise ValueError(
                f"planning horizon exceeds implementation safety cap of "
                f"{MAX_PLANNING_HORIZON_DAYS} days"
            )
        return self


class PlanningWorkWindow(PlanningContract):
    start: AwareDatetime
    end: AwareDatetime

    @model_validator(mode="after")
    def validate_window(self) -> PlanningWorkWindow:
        _require_minute_aligned(self.start, "work_window.start")
        _require_minute_aligned(self.end, "work_window.end")
        if not _instant_before(self.start, self.end):
            raise ValueError("work window end must be after start by instant")
        return self


class RecurrenceSpec(PlanningContract):
    """Recurrence source contract for the intentionally narrow MVP subset."""

    rrule: NonEmptyStr
    timezone: NonEmptyStr
    active_from: AwareDatetime
    active_until: AwareDatetime | None = None

    @model_validator(mode="after")
    def validate_spec(self) -> RecurrenceSpec:
        _validate_timezone(self.timezone)
        _require_minute_aligned(self.active_from, "recurrence.active_from")
        if self.active_until is not None:
            _require_minute_aligned(self.active_until, "recurrence.active_until")
            if not _instant_before(self.active_from, self.active_until):
                raise ValueError("active_until must be after active_from by instant")
        return self


class RecurrenceException(PlanningContract):
    original_start_at: AwareDatetime
    action: RecurrenceExceptionAction
    replacement_start_at: AwareDatetime | None = None
    replacement_end_at: AwareDatetime | None = None

    @model_validator(mode="after")
    def validate_exception(self) -> RecurrenceException:
        _require_minute_aligned(self.original_start_at, "exception.original_start_at")
        has_replacement = (
            self.replacement_start_at is not None or self.replacement_end_at is not None
        )
        if self.action is RecurrenceExceptionAction.CANCELLED:
            if has_replacement:
                raise ValueError("CANCELLED exception must not contain replacement times")
            return self

        if self.replacement_start_at is None or self.replacement_end_at is None:
            raise ValueError("MOVED exception requires replacement_start_at and replacement_end_at")
        _require_minute_aligned(self.replacement_start_at, "exception.replacement_start_at")
        _require_minute_aligned(self.replacement_end_at, "exception.replacement_end_at")
        if not _instant_before(self.replacement_start_at, self.replacement_end_at):
            raise ValueError("replacement_end_at must be after replacement_start_at by instant")
        return self


class PlanningCommitment(PlanningContract):
    commitment_id: NonEmptyStr
    type: CommitmentType
    start_at: AwareDatetime
    end_at: AwareDatetime
    timezone: NonEmptyStr
    recurrence: RecurrenceSpec | None = None
    exceptions: tuple[RecurrenceException, ...] = ()
    source: NonEmptyStr

    @model_validator(mode="after")
    def validate_commitment(self) -> PlanningCommitment:
        _validate_timezone(self.timezone)
        _require_minute_aligned(self.start_at, "commitment.start_at")
        _require_minute_aligned(self.end_at, "commitment.end_at")
        if not _instant_before(self.start_at, self.end_at):
            raise ValueError("commitment end_at must be after start_at by instant")
        if self.recurrence is None and self.exceptions:
            raise ValueError("non-recurring commitment must not contain recurrence exceptions")
        if self.recurrence is not None and self.recurrence.timezone != self.timezone:
            raise ValueError("recurrence timezone must match commitment timezone")

        original_instants = [_as_utc(item.original_start_at) for item in self.exceptions]
        if len(set(original_instants)) != len(original_instants):
            raise ValueError("recurrence exceptions must target unique original occurrence starts")
        return self


class AcceptedCommitment(PlanningContract):
    accepted_commitment_id: NonEmptyStr
    start_at: AwareDatetime
    end_at: AwareDatetime
    source: NonEmptyStr

    @model_validator(mode="after")
    def validate_accepted(self) -> AcceptedCommitment:
        _require_minute_aligned(self.start_at, "accepted.start_at")
        _require_minute_aligned(self.end_at, "accepted.end_at")
        if not _instant_before(self.start_at, self.end_at):
            raise ValueError("accepted commitment end_at must be after start_at by instant")
        return self


class PlanningPreferences(PlanningContract):
    timezone: NonEmptyStr
    max_project_minutes_per_day: StrictInt = Field(ge=0, le=1440)
    preferred_focus_minutes: StrictInt = Field(gt=0)
    buffer_target_minutes: StrictInt = Field(ge=0)

    @model_validator(mode="after")
    def validate_preferences(self) -> PlanningPreferences:
        _validate_timezone(self.timezone)
        return self


class AvailabilityInput(PlanningContract):
    horizon: PlanningHorizon
    work_windows: tuple[PlanningWorkWindow, ...] = ()
    commitments: tuple[PlanningCommitment, ...] = ()
    accepted_commitments: tuple[AcceptedCommitment, ...] = ()
    preferences: PlanningPreferences

    @model_validator(mode="after")
    def validate_input(self) -> AvailabilityInput:
        commitment_ids = [item.commitment_id for item in self.commitments]
        accepted_ids = [item.accepted_commitment_id for item in self.accepted_commitments]
        all_ids = commitment_ids + accepted_ids
        if len(set(all_ids)) != len(all_ids):
            raise ValueError(
                "commitment identifiers must be unique across generic and accepted commitments"
            )
        return self


def _validate_timezone(value: str) -> None:
    try:
        ZoneInfo(value)
    except ZoneInfoNotFoundError as exc:
        raise ValueError(f"unknown IANA timezone: {value}") from exc


def _require_minute_aligned(value: datetime, field_name: str) -> None:
    if value.second != 0 or value.microsecond != 0:
        raise ValueError(f"{field_name} must be minute-aligned")


def _as_utc(value: datetime) -> datetime:
    return value.astimezone(UTC)


def _instant_before(start: datetime, end: datetime) -> bool:
    """Compare instants, never same-zone wall-clock values across a DST fold."""

    return _as_utc(start) < _as_utc(end)
