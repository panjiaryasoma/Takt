from datetime import UTC, datetime, timedelta

import pytest
from pydantic import ValidationError

from engine.scheduler.models import SolverConfig
from packages.contracts import AllocationBlock, CandidateAllocation

START = datetime(2026, 10, 1, 9, 0, tzinfo=UTC)
END = START + timedelta(hours=1)


def _block(**overrides):
    payload = {
        "task_id": "task-a",
        "start": START,
        "end": END,
        "allocated_minutes": 60,
        "availability_source": "derived:work_window:0",
    }
    payload.update(overrides)
    return AllocationBlock(**payload)


def test_allocation_block_accepts_exact_integer_minute_duration() -> None:
    block = _block()
    assert block.allocated_minutes == 60


def test_allocation_block_rejects_duration_mismatch() -> None:
    with pytest.raises(ValidationError):
        _block(allocated_minutes=59)


def test_allocation_block_rejects_naive_datetime() -> None:
    with pytest.raises(ValidationError):
        _block(start=datetime(2026, 10, 1, 9, 0))  # noqa: DTZ001


def test_allocation_block_rejects_non_minute_alignment() -> None:
    with pytest.raises(ValidationError):
        _block(start=START.replace(second=1))


def test_candidate_uses_buffer_minutes_and_typed_blocks() -> None:
    candidate = CandidateAllocation(
        candidate_id="candidate-001",
        work_blocks=(_block(),),
        buffer_minutes=120,
        hard_constraint_violations=(),
        assumptions=("solver effort basis: LIKELY",),
    )
    assert candidate.buffer_minutes == 120
    assert candidate.is_recommendable is True


def test_candidate_rejects_legacy_buffer_hours() -> None:
    with pytest.raises(ValidationError):
        CandidateAllocation(
            candidate_id="candidate-001",
            work_blocks=(_block(),),
            buffer_hours=2,
            hard_constraint_violations=(),
            assumptions=(),
        )


def test_candidate_buffer_is_strict_integer() -> None:
    with pytest.raises(ValidationError):
        CandidateAllocation(
            candidate_id="candidate-001",
            work_blocks=(_block(),),
            buffer_minutes=120.5,
            hard_constraint_violations=(),
            assumptions=(),
        )


def test_candidate_is_frozen() -> None:
    candidate = CandidateAllocation(
        candidate_id="candidate-001",
        work_blocks=(),
        buffer_minutes=0,
        hard_constraint_violations=(),
        assumptions=(),
    )
    with pytest.raises(ValidationError):
        candidate.buffer_minutes = 10


def test_scheduler_public_api_is_narrow() -> None:
    import engine.scheduler as scheduler_api

    assert scheduler_api.__all__ == [
        "SolverConfig",
        "SolverInputError",
        "SolverResult",
        "SolverRunStatus",
        "solve_candidate_allocations",
    ]


def test_scr_003_versions_candidate_allocation_migration() -> None:
    from pathlib import Path

    schema = Path(
        "docs/05_PREPRODUCTION/01_CONTRACTS_ACTIVE/FEATURE_SCHEMA_FINAL.yaml"
    ).read_text(encoding="utf-8")
    scr = Path(
        "docs/05_PREPRODUCTION/01_CONTRACTS_ACTIVE/SCHEMA_CHANGE_REQUEST_003.md"
    ).read_text(encoding="utf-8")

    assert 'schema_version: "3.0.0"' in schema
    assert "buffer_minutes" in schema
    assert "buffer_hours" not in schema
    assert "AllocationBlock" in schema
    assert "SCR-003" in scr
    assert "breaking wire-contract change" in scr


def test_english_and_indonesian_schema_mirrors_share_solver_version() -> None:
    from pathlib import Path

    english = Path(
        "docs/05_PREPRODUCTION/01_CONTRACTS_ACTIVE/FEATURE_SCHEMA_FINAL.yaml"
    ).read_text(encoding="utf-8")
    indonesian = Path(
        "docs/indonesian language/05_PREPRODUCTION/01_CONTRACTS_ACTIVE/"
        "FEATURE_SCHEMA_FINAL.yaml"
    ).read_text(encoding="utf-8")

    for expected in (
        'schema_version: "3.0.0"',
        "AllocationBlock",
        "allocated_minutes",
        "buffer_minutes",
        "work_blocks_type: AllocationBlock",
    ):
        assert expected in english
        assert expected in indonesian


def test_solver_config_only_accepts_likely_effort_basis() -> None:
    with pytest.raises(ValidationError):
        SolverConfig(
            submission_deadline=END,
            buffer_target_minutes=0,
            effort_basis="MAX",
        )
