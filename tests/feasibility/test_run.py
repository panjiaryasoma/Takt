from __future__ import annotations

from datetime import UTC, date, datetime, timedelta

import engine.feasibility.service as feasibility_service
from engine.availability.models import AvailabilityResult, DailyCapacity
from engine.feasibility import assess_feasibility, assess_feasibility_run
from engine.scheduler.models import SolverConfig, SolverResult, SolverRunStatus
from packages.contracts import AvailabilityBlock, AvailabilityType, CandidateAllocation, Task
from packages.contracts.workload import WorkloadInput

START = datetime(2026, 10, 1, 9, 0, tzinfo=UTC)


def _workload() -> WorkloadInput:
    return WorkloadInput(
        tasks=(
            Task(
                task_id="core",
                name="Core",
                mandatory=True,
                dependencies=(),
                effort_min_minutes=60,
                effort_likely_minutes=120,
                effort_max_minutes=180,
                assumptions=(),
            ),
            Task(
                task_id="optional",
                name="Optional",
                mandatory=False,
                dependencies=(),
                effort_min_minutes=30,
                effort_likely_minutes=120,
                effort_max_minutes=120,
                assumptions=(),
            ),
        )
    )


def _availability() -> AvailabilityResult:
    return AvailabilityResult(
        timezone="UTC",
        horizon_start=START,
        horizon_end=START + timedelta(hours=8),
        busy_blocks=(),
        available_blocks=(
            AvailabilityBlock(
                start=START,
                end=START + timedelta(hours=8),
                timezone="UTC",
                source="work-window",
                availability_type=AvailabilityType.AVAILABLE,
            ),
        ),
        daily_capacity=(
            DailyCapacity(
                local_date=date(2026, 10, 1),
                calendar_free_minutes=480,
                accepted_project_minutes=0,
                configured_project_limit_minutes=480,
                remaining_project_capacity_minutes=480,
                usable_project_minutes=480,
            ),
        ),
    )


def _config() -> SolverConfig:
    return SolverConfig(
        submission_deadline=START + timedelta(hours=8),
        buffer_target_minutes=0,
    )


def _result(buffer_minutes: int) -> SolverResult:
    return SolverResult(
        status=SolverRunStatus.OPTIMAL,
        candidate_allocations=(
            CandidateAllocation(
                candidate_id="candidate-001",
                work_blocks=(),
                buffer_minutes=buffer_minutes,
                hard_constraint_violations=(),
                assumptions=(),
            ),
        ),
        reason_codes=(),
    )


# FEAS-RUN-001, FEAS-RUN-002, FEAS-RUN-003
def test_feasibility_run_captures_exact_likely_result_with_four_solver_calls(
    monkeypatch,
) -> None:
    calls = []
    buffers = iter((400, 300, 200, 100))

    def fake_solver(_availability, workload, _config):
        result = _result(next(buffers))
        calls.append((workload.required_effort.likely_minutes, result))
        return result

    monkeypatch.setattr(feasibility_service, "solve_candidate_allocations", fake_solver)

    run = assess_feasibility_run(_availability(), _workload(), _config())

    assert len(calls) == 4
    assert [item[0] for item in calls] == [60, 120, 180, 240]
    assert run.likely_solver_result == calls[1][1]
    assert run.likely_solver_result.candidate_allocations[0].buffer_minutes == 300
    assert run.assessment.scenario_results[1].buffer_minutes == 300


# FEAS-RUN-004
def test_compatibility_api_returns_same_semantic_assessment(monkeypatch) -> None:
    def fake_solver(_availability, workload, _config):
        return _result(1000 - workload.required_effort.likely_minutes)

    monkeypatch.setattr(feasibility_service, "solve_candidate_allocations", fake_solver)

    run_assessment = assess_feasibility_run(
        _availability(),
        _workload(),
        _config(),
    ).assessment
    compatibility_assessment = assess_feasibility(
        _availability(),
        _workload(),
        _config(),
    )

    assert compatibility_assessment == run_assessment


# FEAS-RUN-005
def test_feasibility_run_captures_semantic_baseline_from_same_invocation(monkeypatch) -> None:
    captured_baselines = []
    real_analyze_workload = feasibility_service.analyze_workload

    def capture_baseline(workload):
        analysis = real_analyze_workload(workload)
        captured_baselines.append(analysis)
        return analysis

    def fake_solver(_availability, workload, _config):
        return _result(1000 - workload.required_effort.likely_minutes)

    monkeypatch.setattr(feasibility_service, "analyze_workload", capture_baseline)
    monkeypatch.setattr(feasibility_service, "solve_candidate_allocations", fake_solver)

    run = assess_feasibility_run(_availability(), _workload(), _config())

    assert len(captured_baselines) == 1
    assert run.baseline_workload_analysis == captured_baselines[0]
    assert run.baseline_workload_analysis.assumptions == run.assessment.assumptions
