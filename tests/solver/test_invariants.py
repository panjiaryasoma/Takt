from datetime import UTC, date, datetime, timedelta

from engine.availability.models import AvailabilityResult, DailyCapacity
from engine.scheduler.invariants import candidate_hard_constraint_violations
from engine.scheduler.models import SolverConfig
from packages.contracts import AllocationBlock, AvailabilityBlock, AvailabilityType
from packages.contracts.models import CandidateAllocation, Task
from packages.contracts.workload import EffortRange, WorkloadAnalysis

START = datetime(2026, 10, 1, 9, 0, tzinfo=UTC)


def _availability(capacity=240):
    return AvailabilityResult(
        timezone="UTC",
        horizon_start=START,
        horizon_end=START + timedelta(hours=8),
        busy_blocks=(),
        available_blocks=(
            AvailabilityBlock(
                start=START,
                end=START + timedelta(hours=4),
                timezone="UTC",
                source="derived:work_window:0",
                availability_type=AvailabilityType.AVAILABLE,
            ),
        ),
        daily_capacity=(
            DailyCapacity(
                local_date=date(2026, 10, 1),
                calendar_free_minutes=240,
                accepted_project_minutes=0,
                configured_project_limit_minutes=capacity,
                remaining_project_capacity_minutes=capacity,
                usable_project_minutes=min(240, capacity),
            ),
        ),
    )


def _workload():
    a = Task(
        task_id="a",
        name="A",
        mandatory=True,
        dependencies=(),
        effort_min_minutes=60,
        effort_likely_minutes=60,
        effort_max_minutes=60,
        assumptions=(),
    )
    b = Task(
        task_id="b",
        name="B",
        mandatory=True,
        dependencies=("a",),
        effort_min_minutes=60,
        effort_likely_minutes=60,
        effort_max_minutes=60,
        assumptions=(),
    )
    return WorkloadAnalysis(
        tasks=(a, b),
        topological_order=("a", "b"),
        required_task_ids=("a", "b"),
        declared_mandatory_effort=EffortRange(
            min_minutes=120,
            likely_minutes=120,
            max_minutes=120,
        ),
        required_effort=EffortRange(
            min_minutes=120,
            likely_minutes=120,
            max_minutes=120,
        ),
        optional_effort=EffortRange(min_minutes=0, likely_minutes=0, max_minutes=0),
        assumptions=(),
    )


def _block(task_id, start_minute, duration=60):
    start = START + timedelta(minutes=start_minute)
    return AllocationBlock(
        task_id=task_id,
        start=start,
        end=start + timedelta(minutes=duration),
        allocated_minutes=duration,
        availability_source="derived:work_window:0",
    )


def _candidate(blocks, buffer=120):
    return CandidateAllocation(
        candidate_id="candidate-001",
        work_blocks=tuple(blocks),
        buffer_minutes=buffer,
        hard_constraint_violations=(),
        assumptions=(),
    )


def _config(buffer=0):
    return SolverConfig(
        submission_deadline=START + timedelta(hours=4),
        buffer_target_minutes=buffer,
    )


def test_valid_candidate_has_zero_hard_violations() -> None:
    candidate = _candidate((_block("a", 0), _block("b", 60)))
    assert candidate_hard_constraint_violations(
        candidate,
        _availability(),
        _workload(),
        _config(),
    ) == ()


def test_overlap_is_detected() -> None:
    candidate = _candidate((_block("a", 0), _block("b", 30)))
    violations = candidate_hard_constraint_violations(
        candidate,
        _availability(),
        _workload(),
        _config(),
    )
    assert "ALLOCATION_OVERLAP" in violations


def test_finish_to_start_dependency_is_detected() -> None:
    candidate = _candidate((_block("b", 0), _block("a", 60)))
    violations = candidate_hard_constraint_violations(
        candidate,
        _availability(),
        _workload(),
        _config(),
    )
    assert "DEPENDENCY_ORDER:a->b" in violations


def test_required_effort_mismatch_is_detected() -> None:
    candidate = _candidate((_block("a", 0, 30), _block("b", 60)))
    violations = candidate_hard_constraint_violations(
        candidate,
        _availability(),
        _workload(),
        _config(),
    )
    assert "REQUIRED_EFFORT_MISMATCH:a" in violations


def test_outside_available_block_is_detected() -> None:
    candidate = _candidate((_block("a", 0), _block("b", 240)))
    violations = candidate_hard_constraint_violations(
        candidate,
        _availability(),
        _workload(),
        _config(),
    )
    assert "OUTSIDE_AVAILABLE_BLOCK" in violations


def test_daily_capacity_violation_is_detected() -> None:
    candidate = _candidate((_block("a", 0), _block("b", 60)), buffer=0)
    violations = candidate_hard_constraint_violations(
        candidate,
        _availability(capacity=90),
        _workload(),
        _config(),
    )
    assert "DAILY_CAPACITY:2026-10-01" in violations


def test_buffer_target_violation_is_detected() -> None:
    candidate = _candidate((_block("a", 0), _block("b", 60)), buffer=120)
    violations = candidate_hard_constraint_violations(
        candidate,
        _availability(),
        _workload(),
        _config(buffer=180),
    )
    assert "BUFFER_TARGET_NOT_MET" in violations


def test_availability_source_mismatch_is_detected() -> None:
    block = _block("a", 0).model_copy(update={"availability_source": "wrong-source"})
    candidate = _candidate((block, _block("b", 60)))
    violations = candidate_hard_constraint_violations(
        candidate,
        _availability(),
        _workload(),
        _config(),
    )
    assert "AVAILABILITY_SOURCE_MISMATCH" in violations


def test_busy_overlap_is_detected_even_inside_available_block() -> None:
    availability = _availability()
    busy = AvailabilityBlock(
        start=START + timedelta(minutes=30),
        end=START + timedelta(minutes=90),
        timezone="UTC",
        source="fixed-meeting",
        availability_type=AvailabilityType.FIXED_BUSY,
    )
    contradictory = availability.model_copy(update={"busy_blocks": (busy,)})
    candidate = _candidate((_block("a", 0), _block("b", 60)))
    violations = candidate_hard_constraint_violations(
        candidate,
        contradictory,
        _workload(),
        _config(),
    )
    assert "BUSY_OVERLAP" in violations
