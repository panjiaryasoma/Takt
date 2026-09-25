from __future__ import annotations

import json
from datetime import datetime, timedelta
from pathlib import Path

import pytest
from pydantic import ValidationError

from engine.availability import (
    InvalidLocalTimeError,
    InvalidRecurrenceExceptionError,
    UnsupportedRecurrenceRuleError,
    build_availability,
)
from packages.contracts import (
    MAX_PLANNING_HORIZON_DAYS,
    AcceptedCommitment,
    AvailabilityBlock,
    AvailabilityInput,
    AvailabilityType,
    CommitmentType,
    PlanningCommitment,
    PlanningHorizon,
    PlanningPreferences,
    PlanningWorkWindow,
    RecurrenceException,
    RecurrenceExceptionAction,
    RecurrenceSpec,
)


def dt(value: str) -> datetime:
    return datetime.fromisoformat(value)


def horizon(
    start: str = "2026-09-28T00:00:00+07:00",
    end: str = "2026-09-29T00:00:00+07:00",
) -> PlanningHorizon:
    return PlanningHorizon(start=dt(start), end=dt(end))


def prefs(
    timezone: str = "Asia/Jakarta",
    limit: int = 180,
    focus: int = 90,
    buffer: int = 60,
) -> PlanningPreferences:
    return PlanningPreferences(
        timezone=timezone,
        max_project_minutes_per_day=limit,
        preferred_focus_minutes=focus,
        buffer_target_minutes=buffer,
    )


def window(
    start: str = "2026-09-28T08:00:00+07:00",
    end: str = "2026-09-28T22:00:00+07:00",
) -> PlanningWorkWindow:
    return PlanningWorkWindow(start=dt(start), end=dt(end))


def commitment(
    commitment_id: str,
    start: str,
    end: str,
    kind: CommitmentType = CommitmentType.FIXED,
    timezone: str = "Asia/Jakarta",
    recurrence: RecurrenceSpec | None = None,
    exceptions: tuple[RecurrenceException, ...] = (),
) -> PlanningCommitment:
    return PlanningCommitment(
        commitment_id=commitment_id,
        type=kind,
        start_at=dt(start),
        end_at=dt(end),
        timezone=timezone,
        recurrence=recurrence,
        exceptions=exceptions,
        source="fixture",
    )


def recurrence(
    rrule: str,
    active_from: str,
    timezone: str = "Asia/Jakarta",
    active_until: str | None = None,
) -> RecurrenceSpec:
    return RecurrenceSpec(
        rrule=rrule,
        timezone=timezone,
        active_from=dt(active_from),
        active_until=dt(active_until) if active_until else None,
    )


def accepted(
    accepted_id: str,
    start: str,
    end: str,
) -> AcceptedCommitment:
    return AcceptedCommitment(
        accepted_commitment_id=accepted_id,
        start_at=dt(start),
        end_at=dt(end),
        source="accepted",
    )


def availability_input(
    *,
    planning_horizon: PlanningHorizon | None = None,
    work_windows: tuple[PlanningWorkWindow, ...] | None = None,
    commitments: tuple[PlanningCommitment, ...] = (),
    accepted_commitments: tuple[AcceptedCommitment, ...] = (),
    preferences: PlanningPreferences | None = None,
) -> AvailabilityInput:
    return AvailabilityInput(
        horizon=planning_horizon or horizon(),
        work_windows=(window(),) if work_windows is None else work_windows,
        commitments=commitments,
        accepted_commitments=accepted_commitments,
        preferences=preferences or prefs(),
    )


# AVAIL-001
def test_single_fixed_commitment_produces_correct_free_gaps() -> None:
    item = commitment(
        "class",
        "2026-09-28T10:00:00+07:00",
        "2026-09-28T12:00:00+07:00",
    )
    result = build_availability(availability_input(commitments=(item,)))
    assert [(b.start.hour, b.end.hour) for b in result.available_blocks] == [(8, 10), (12, 22)]
    assert result.busy_blocks[0].availability_type is AvailabilityType.FIXED_BUSY


# AVAIL-002
def test_weekly_recurrence_expands_correctly() -> None:
    rule = recurrence(
        "FREQ=WEEKLY;BYDAY=MO,WE",
        "2026-09-28T09:00:00+07:00",
    )
    item = commitment(
        "course",
        "2026-09-28T09:00:00+07:00",
        "2026-09-28T10:00:00+07:00",
        recurrence=rule,
    )
    result = build_availability(
        availability_input(
            planning_horizon=horizon(
                "2026-09-28T00:00:00+07:00",
                "2026-10-08T00:00:00+07:00",
            ),
            work_windows=(),
            commitments=(item,),
        )
    )
    assert [b.start.date().isoformat() for b in result.busy_blocks] == [
        "2026-09-28",
        "2026-09-30",
        "2026-10-05",
        "2026-10-07",
    ]


# AVAIL-003
def test_cancelled_recurrence_occurrence_disappears() -> None:
    exception = RecurrenceException(
        original_start_at=dt("2026-10-05T09:00:00+07:00"),
        action=RecurrenceExceptionAction.CANCELLED,
    )
    item = commitment(
        "course",
        "2026-09-28T09:00:00+07:00",
        "2026-09-28T10:00:00+07:00",
        recurrence=recurrence("FREQ=WEEKLY", "2026-09-28T09:00:00+07:00"),
        exceptions=(exception,),
    )
    result = build_availability(
        availability_input(
            planning_horizon=horizon(
                "2026-09-28T00:00:00+07:00",
                "2026-10-13T00:00:00+07:00",
            ),
            work_windows=(),
            commitments=(item,),
        )
    )
    assert [b.start.date().isoformat() for b in result.busy_blocks] == [
        "2026-09-28",
        "2026-10-12",
    ]


# AVAIL-004
def test_moved_occurrence_replaces_original() -> None:
    exception = RecurrenceException(
        original_start_at=dt("2026-10-05T09:00:00+07:00"),
        action=RecurrenceExceptionAction.MOVED,
        replacement_start_at=dt("2026-10-05T13:00:00+07:00"),
        replacement_end_at=dt("2026-10-05T14:00:00+07:00"),
    )
    item = commitment(
        "course",
        "2026-09-28T09:00:00+07:00",
        "2026-09-28T10:00:00+07:00",
        recurrence=recurrence("FREQ=WEEKLY", "2026-09-28T09:00:00+07:00"),
        exceptions=(exception,),
    )
    result = build_availability(
        availability_input(
            planning_horizon=horizon(
                "2026-10-05T00:00:00+07:00",
                "2026-10-06T00:00:00+07:00",
            ),
            work_windows=(),
            commitments=(item,),
        )
    )
    assert [(b.start.hour, b.end.hour) for b in result.busy_blocks] == [(13, 14)]


# AVAIL-005
def test_accepted_commitment_is_hard_busy() -> None:
    result = build_availability(
        availability_input(
            accepted_commitments=(
                accepted(
                    "approved",
                    "2026-09-28T19:00:00+07:00",
                    "2026-09-28T21:00:00+07:00",
                ),
            )
        )
    )
    assert any(
        block.availability_type is AvailabilityType.ACCEPTED_PROJECT_COMMITMENT
        for block in result.busy_blocks
    )


# AVAIL-006
def test_fixed_wins_over_flexible_and_busy_output_is_non_overlapping() -> None:
    flex = commitment(
        "gym",
        "2026-09-28T14:00:00+07:00",
        "2026-09-28T16:00:00+07:00",
        CommitmentType.FLEXIBLE,
    )
    fixed = commitment(
        "class",
        "2026-09-28T15:00:00+07:00",
        "2026-09-28T17:00:00+07:00",
    )
    result = build_availability(availability_input(commitments=(flex, fixed)))
    assert [
        (b.start.hour, b.end.hour, b.availability_type)
        for b in result.busy_blocks
    ] == [
        (14, 15, AvailabilityType.FLEXIBLE_BUSY),
        (15, 16, AvailabilityType.FIXED_BUSY),
        (16, 17, AvailabilityType.FIXED_BUSY),
    ]
    assert "fixture:gym" in result.busy_blocks[1].source
    assert "fixture:class" in result.busy_blocks[1].source


# AVAIL-007
def test_overlapping_fixed_events_are_segmented_deterministically() -> None:
    a = commitment("a", "2026-09-28T08:00:00+07:00", "2026-09-28T10:00:00+07:00")
    b = commitment("b", "2026-09-28T09:00:00+07:00", "2026-09-28T11:00:00+07:00")
    result = build_availability(availability_input(commitments=(a, b)))
    assert [(x.start.hour, x.end.hour) for x in result.busy_blocks] == [(8, 9), (9, 10), (10, 11)]
    assert result.busy_blocks[1].source == "fixture:a|fixture:b"


# AVAIL-008
def test_cross_midnight_commitment_blocks_both_days() -> None:
    item = commitment(
        "overnight",
        "2026-09-28T21:00:00+07:00",
        "2026-09-29T09:00:00+07:00",
    )
    result = build_availability(
        availability_input(
            planning_horizon=horizon(
                "2026-09-28T00:00:00+07:00",
                "2026-09-30T00:00:00+07:00",
            ),
            work_windows=(
                window("2026-09-28T08:00:00+07:00", "2026-09-28T22:00:00+07:00"),
                window("2026-09-29T08:00:00+07:00", "2026-09-29T22:00:00+07:00"),
            ),
            commitments=(item,),
        )
    )
    assert [(b.start.isoformat(), b.end.isoformat()) for b in result.available_blocks] == [
        ("2026-09-28T08:00:00+07:00", "2026-09-28T21:00:00+07:00"),
        ("2026-09-29T09:00:00+07:00", "2026-09-29T22:00:00+07:00"),
    ]


# AVAIL-009
def test_different_timezone_preserves_instant() -> None:
    item = commitment(
        "utc-event",
        "2026-09-28T01:00:00+00:00",
        "2026-09-28T03:00:00+00:00",
        timezone="UTC",
    )
    result = build_availability(availability_input(commitments=(item,)))
    assert result.busy_blocks[0].start.isoformat() == "2026-09-28T08:00:00+07:00"
    assert result.busy_blocks[0].end.isoformat() == "2026-09-28T10:00:00+07:00"


# AVAIL-010 + DST gate
def test_nonexistent_dst_recurrence_time_is_explicit_error() -> None:
    ny_prefs = prefs(timezone="America/New_York")
    item = commitment(
        "dst",
        "2026-03-01T02:30:00-05:00",
        "2026-03-01T03:30:00-05:00",
        timezone="America/New_York",
        recurrence=recurrence(
            "FREQ=WEEKLY",
            "2026-03-01T02:30:00-05:00",
            timezone="America/New_York",
        ),
    )
    with pytest.raises(InvalidLocalTimeError, match="nonexistent"):
        build_availability(
            availability_input(
                planning_horizon=horizon(
                    "2026-03-07T00:00:00-05:00",
                    "2026-03-10T00:00:00-04:00",
                ),
                work_windows=(),
                commitments=(item,),
                preferences=ny_prefs,
            )
        )


def test_ambiguous_dst_recurrence_time_is_explicit_error() -> None:
    item = commitment(
        "dst-fall",
        "2026-10-25T01:30:00-04:00",
        "2026-10-25T02:30:00-04:00",
        timezone="America/New_York",
        recurrence=recurrence(
            "FREQ=WEEKLY",
            "2026-10-25T01:30:00-04:00",
            timezone="America/New_York",
        ),
    )
    with pytest.raises(InvalidLocalTimeError, match="ambiguous"):
        build_availability(
            availability_input(
                planning_horizon=horizon(
                    "2026-10-31T00:00:00-04:00",
                    "2026-11-03T00:00:00-05:00",
                ),
                work_windows=(),
                commitments=(item,),
                preferences=prefs(timezone="America/New_York"),
            )
        )


# AVAIL-011
def test_horizon_clips_work_windows_and_busy() -> None:
    result = build_availability(
        availability_input(
            planning_horizon=horizon(
                "2026-09-28T10:30:00+07:00",
                "2026-09-28T13:15:00+07:00",
            ),
            work_windows=(window(),),
        )
    )
    assert [(b.start.isoformat(), b.end.isoformat()) for b in result.available_blocks] == [
        ("2026-09-28T10:30:00+07:00", "2026-09-28T13:15:00+07:00")
    ]


# AVAIL-012
def test_outside_explicit_work_window_is_not_available() -> None:
    result = build_availability(
        availability_input(
            work_windows=(
                window("2026-09-28T09:00:00+07:00", "2026-09-28T12:00:00+07:00"),
                window("2026-09-28T18:00:00+07:00", "2026-09-28T22:00:00+07:00"),
            )
        )
    )
    assert [(b.start.hour, b.end.hour) for b in result.available_blocks] == [(9, 12), (18, 22)]


def test_no_work_window_means_no_schedulable_available_time() -> None:
    result = build_availability(availability_input(work_windows=()))
    assert result.available_blocks == ()
    assert result.daily_capacity[0].calendar_free_minutes == 0


# AVAIL-013
def test_daily_limit_does_not_trim_raw_availability() -> None:
    result = build_availability(availability_input(preferences=prefs(limit=180)))
    assert [(b.start.hour, b.end.hour) for b in result.available_blocks] == [(8, 22)]
    assert result.daily_capacity[0].calendar_free_minutes == 14 * 60
    assert result.daily_capacity[0].configured_project_limit_minutes == 180
    assert result.daily_capacity[0].usable_project_minutes == 180


# AVAIL-014
def test_unsupported_rrule_is_explicit_error() -> None:
    item = commitment(
        "bad-rule",
        "2026-09-28T09:00:00+07:00",
        "2026-09-28T10:00:00+07:00",
        recurrence=recurrence(
            "FREQ=WEEKLY;COUNT=4",
            "2026-09-28T09:00:00+07:00",
        ),
    )
    with pytest.raises(UnsupportedRecurrenceRuleError, match="COUNT"):
        build_availability(availability_input(work_windows=(), commitments=(item,)))


# AVAIL-015
def test_cancelled_exception_rejects_replacement_fields() -> None:
    with pytest.raises(ValidationError):
        RecurrenceException(
            original_start_at=dt("2026-10-05T09:00:00+07:00"),
            action=RecurrenceExceptionAction.CANCELLED,
            replacement_start_at=dt("2026-10-05T13:00:00+07:00"),
        )


def test_exception_on_non_recurring_commitment_is_rejected() -> None:
    exception = RecurrenceException(
        original_start_at=dt("2026-10-05T09:00:00+07:00"),
        action=RecurrenceExceptionAction.CANCELLED,
    )
    with pytest.raises(ValidationError, match="non-recurring"):
        commitment(
            "one-off",
            "2026-09-28T09:00:00+07:00",
            "2026-09-28T10:00:00+07:00",
            exceptions=(exception,),
        )


def test_orphan_recurrence_exception_is_explicit_error() -> None:
    exception = RecurrenceException(
        original_start_at=dt("2026-09-29T09:00:00+07:00"),  # Tuesday, series is Monday.
        action=RecurrenceExceptionAction.CANCELLED,
    )
    item = commitment(
        "weekly",
        "2026-09-28T09:00:00+07:00",
        "2026-09-28T10:00:00+07:00",
        recurrence=recurrence("FREQ=WEEKLY", "2026-09-28T09:00:00+07:00"),
        exceptions=(exception,),
    )
    with pytest.raises(InvalidRecurrenceExceptionError):
        build_availability(availability_input(work_windows=(), commitments=(item,)))


def test_occurrence_outside_horizon_moved_inside_is_included() -> None:
    exception = RecurrenceException(
        original_start_at=dt("2026-10-12T09:00:00+07:00"),
        action=RecurrenceExceptionAction.MOVED,
        replacement_start_at=dt("2026-10-08T13:00:00+07:00"),
        replacement_end_at=dt("2026-10-08T14:00:00+07:00"),
    )
    item = commitment(
        "weekly",
        "2026-09-28T09:00:00+07:00",
        "2026-09-28T10:00:00+07:00",
        recurrence=recurrence("FREQ=WEEKLY", "2026-09-28T09:00:00+07:00"),
        exceptions=(exception,),
    )
    result = build_availability(
        availability_input(
            planning_horizon=horizon(
                "2026-10-07T00:00:00+07:00",
                "2026-10-10T00:00:00+07:00",
            ),
            work_windows=(),
            commitments=(item,),
        )
    )
    assert [(b.start.isoformat(), b.end.isoformat()) for b in result.busy_blocks] == [
        ("2026-10-08T13:00:00+07:00", "2026-10-08T14:00:00+07:00")
    ]


# AVAIL-016
def test_same_input_produces_identical_ordered_output() -> None:
    data = availability_input(
        commitments=(
            commitment("b", "2026-09-28T12:00:00+07:00", "2026-09-28T13:00:00+07:00"),
            commitment("a", "2026-09-28T09:00:00+07:00", "2026-09-28T10:00:00+07:00"),
        )
    )
    assert build_availability(data).model_dump() == build_availability(data).model_dump()


# Contract completeness / strict boundary gates.
def test_preferences_include_focus_and_buffer() -> None:
    value = prefs()
    assert value.preferred_focus_minutes == 90
    assert value.buffer_target_minutes == 60


def test_planning_models_forbid_unknown_fields_and_numeric_coercion() -> None:
    with pytest.raises(ValidationError):
        PlanningPreferences.model_validate(
            {
                "timezone": "Asia/Jakarta",
                "max_project_minutes_per_day": "180",
                "preferred_focus_minutes": 90,
                "buffer_target_minutes": 60,
                "typo": True,
            }
        )

    with pytest.raises(ValidationError):
        RecurrenceSpec.model_validate(
            {
                "rrule": "FREQ=WEEKLY",
                "timezone": "Asia/Jakarta",
                "active_from": "2026-09-28T09:00:00+07:00",
                "intervall": 2,
            }
        )


def test_models_are_frozen_against_post_validation_mutation() -> None:
    item = commitment("frozen", "2026-09-28T09:00:00+07:00", "2026-09-28T10:00:00+07:00")
    with pytest.raises(ValidationError):
        item.type = CommitmentType.FLEXIBLE  # type: ignore[misc]


def test_weekly_interval_uses_monday_based_week_buckets() -> None:
    item = commitment(
        "interval",
        "2026-09-30T09:00:00+07:00",  # Wednesday
        "2026-09-30T10:00:00+07:00",
        recurrence=recurrence(
            "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR",
            "2026-09-30T09:00:00+07:00",
        ),
    )
    result = build_availability(
        availability_input(
            planning_horizon=horizon(
                "2026-09-30T00:00:00+07:00",
                "2026-10-20T00:00:00+07:00",
            ),
            work_windows=(),
            commitments=(item,),
        )
    )
    assert [b.start.date().isoformat() for b in result.busy_blocks] == [
        "2026-10-02",
        "2026-10-12",
        "2026-10-16",
    ]


def test_horizon_is_explicitly_bounded() -> None:
    start = dt("2026-01-01T00:00:00+07:00")
    with pytest.raises(ValidationError, match="safety cap"):
        PlanningHorizon(
            start=start,
            end=start + timedelta(days=MAX_PLANNING_HORIZON_DAYS + 1),
        )


def test_overlapping_accepted_commitments_are_union_counted() -> None:
    result = build_availability(
        availability_input(
            accepted_commitments=(
                accepted("a", "2026-09-28T19:00:00+07:00", "2026-09-28T20:00:00+07:00"),
                accepted("b", "2026-09-28T19:30:00+07:00", "2026-09-28T20:30:00+07:00"),
            ),
            preferences=prefs(limit=180),
        )
    )
    day = result.daily_capacity[0]
    assert day.accepted_project_minutes == 90
    assert day.remaining_project_capacity_minutes == 90


def test_accepted_precedence_wins_and_preserves_contributing_sources() -> None:
    generic = commitment(
        "class",
        "2026-09-28T19:00:00+07:00",
        "2026-09-28T21:00:00+07:00",
    )
    approved = accepted(
        "project",
        "2026-09-28T20:00:00+07:00",
        "2026-09-28T22:00:00+07:00",
    )
    result = build_availability(
        availability_input(commitments=(generic,), accepted_commitments=(approved,))
    )
    overlap = [b for b in result.busy_blocks if b.start.hour == 20 and b.end.hour == 21][0]
    assert overlap.availability_type is AvailabilityType.ACCEPTED_PROJECT_COMMITMENT
    assert "fixture:class" in overlap.source
    assert "accepted:project" in overlap.source


def test_all_temporal_inputs_must_be_minute_aligned() -> None:
    with pytest.raises(ValidationError, match="minute-aligned"):
        PlanningWorkWindow(
            start=dt("2026-09-28T09:00:30+07:00"),
            end=dt("2026-09-28T10:00:00+07:00"),
        )
    with pytest.raises(ValidationError, match="minute-aligned"):
        accepted(
            "seconds",
            "2026-09-28T19:00:30+07:00",
            "2026-09-28T19:01:00+07:00",
        )


def test_availability_block_is_timezone_aware_ordered_and_iana_valid() -> None:
    with pytest.raises(ValidationError):
        AvailabilityBlock(
            start=datetime(2026, 9, 28, 9, 0),
            end=dt("2026-09-28T10:00:00+07:00"),
            timezone="Asia/Jakarta",
            source="x",
            availability_type=AvailabilityType.AVAILABLE,
        )
    with pytest.raises(ValidationError, match="unknown IANA"):
        AvailabilityBlock(
            start=dt("2026-09-28T09:00:00+07:00"),
            end=dt("2026-09-28T10:00:00+07:00"),
            timezone="Mars/Olympus",
            source="x",
            availability_type=AvailabilityType.AVAILABLE,
        )


def test_generic_and_accepted_commitment_cannot_share_same_identifier() -> None:
    generic = commitment(
        "same",
        "2026-09-28T09:00:00+07:00",
        "2026-09-28T10:00:00+07:00",
    )
    approved = accepted(
        "same",
        "2026-09-28T19:00:00+07:00",
        "2026-09-28T20:00:00+07:00",
    )
    with pytest.raises(ValidationError, match="unique"):
        availability_input(commitments=(generic,), accepted_commitments=(approved,))


def test_calendar_fixture_executes_end_to_end() -> None:
    payload = json.loads(
        Path("tests/fixtures/availability/calendar_001.json").read_text()
    )
    data = AvailabilityInput.model_validate(payload)
    result = build_availability(data)
    assert [
        (b.start.hour, b.end.hour, b.availability_type)
        for b in result.busy_blocks
    ] == [
        (8, 12, AvailabilityType.FIXED_BUSY),
        (17, 18, AvailabilityType.FLEXIBLE_BUSY),
        (20, 21, AvailabilityType.ACCEPTED_PROJECT_COMMITMENT),
    ]
    assert result.daily_capacity[0].accepted_project_minutes == 60

# DST-FOLD-001
def test_one_off_fold_interval_is_60_minutes_fixed_busy() -> None:
    from zoneinfo import ZoneInfo

    ny = ZoneInfo("America/New_York")
    start = datetime(2026, 11, 1, 1, 30, tzinfo=ny, fold=0)
    end = datetime(2026, 11, 1, 1, 30, tzinfo=ny, fold=1)
    item = PlanningCommitment(
        commitment_id="fold-fixed",
        type=CommitmentType.FIXED,
        start_at=start,
        end_at=end,
        timezone="America/New_York",
        source="fixture",
    )
    result = build_availability(
        availability_input(
            planning_horizon=PlanningHorizon(
                start=datetime(2026, 11, 1, 0, 0, tzinfo=ny, fold=0),
                end=datetime(2026, 11, 1, 3, 0, tzinfo=ny, fold=1),
            ),
            work_windows=(),
            commitments=(item,),
            preferences=prefs(timezone="America/New_York"),
        )
    )
    block = result.busy_blocks[0]
    assert block.start.isoformat() == "2026-11-01T01:30:00-04:00"
    assert block.end.isoformat() == "2026-11-01T01:30:00-05:00"
    assert int((block.end.timestamp() - block.start.timestamp()) // 60) == 60


# DST-FOLD-002
def test_fold_work_window_is_60_minutes_available() -> None:
    from zoneinfo import ZoneInfo

    ny = ZoneInfo("America/New_York")
    result = build_availability(
        availability_input(
            planning_horizon=PlanningHorizon(
                start=datetime(2026, 11, 1, 0, 0, tzinfo=ny, fold=0),
                end=datetime(2026, 11, 1, 3, 0, tzinfo=ny, fold=1),
            ),
            work_windows=(
                PlanningWorkWindow(
                    start=datetime(2026, 11, 1, 1, 0, tzinfo=ny, fold=0),
                    end=datetime(2026, 11, 1, 1, 0, tzinfo=ny, fold=1),
                ),
            ),
            preferences=prefs(timezone="America/New_York"),
        )
    )
    assert len(result.available_blocks) == 1
    block = result.available_blocks[0]
    assert block.start.isoformat() == "2026-11-01T01:00:00-04:00"
    assert block.end.isoformat() == "2026-11-01T01:00:00-05:00"
    assert result.daily_capacity[0].calendar_free_minutes == 60


# DST-FOLD-003
def test_fold_accepted_commitment_counts_60_elapsed_minutes() -> None:
    from zoneinfo import ZoneInfo

    ny = ZoneInfo("America/New_York")
    approved = AcceptedCommitment(
        accepted_commitment_id="fold-accepted",
        start_at=datetime(2026, 11, 1, 1, 30, tzinfo=ny, fold=0),
        end_at=datetime(2026, 11, 1, 1, 30, tzinfo=ny, fold=1),
        source="accepted",
    )
    result = build_availability(
        availability_input(
            planning_horizon=PlanningHorizon(
                start=datetime(2026, 11, 1, 0, 0, tzinfo=ny, fold=0),
                end=datetime(2026, 11, 1, 3, 0, tzinfo=ny, fold=1),
            ),
            work_windows=(),
            accepted_commitments=(approved,),
            preferences=prefs(timezone="America/New_York"),
        )
    )
    assert result.daily_capacity[0].accepted_project_minutes == 60


# DST-FOLD-004
def test_contract_accepts_zoneinfo_fold_interval_by_instant_order() -> None:
    from zoneinfo import ZoneInfo

    ny = ZoneInfo("America/New_York")
    block = AvailabilityBlock(
        start=datetime(2026, 11, 1, 1, 30, tzinfo=ny, fold=0),
        end=datetime(2026, 11, 1, 1, 30, tzinfo=ny, fold=1),
        timezone="America/New_York",
        source="fixture",
        availability_type=AvailabilityType.FIXED_BUSY,
    )
    assert block.end.timestamp() - block.start.timestamp() == 3600
