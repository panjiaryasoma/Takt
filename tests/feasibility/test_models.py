from __future__ import annotations

import pytest
from pydantic import ValidationError

from engine.feasibility.models import (
    FeasibilityAssessment,
    FeasibilityScenario,
    FeasibilityScenarioResult,
)
from engine.scheduler.models import SolverRunStatus
from packages.contracts.enums import FeasibilityStatus


def _result(
    scenario: FeasibilityScenario,
    status: SolverRunStatus = SolverRunStatus.OPTIMAL,
) -> FeasibilityScenarioResult:
    feasible = status in {SolverRunStatus.OPTIMAL, SolverRunStatus.FEASIBLE}
    return FeasibilityScenarioResult(
        scenario=scenario,
        solver_status=status,
        candidate_id="candidate-001" if feasible else None,
        buffer_minutes=60 if feasible else None,
    )


def _all_results() -> tuple[FeasibilityScenarioResult, ...]:
    return (
        _result(FeasibilityScenario.MIN),
        _result(FeasibilityScenario.LIKELY),
        _result(FeasibilityScenario.MAX),
        _result(FeasibilityScenario.FULL_SCOPE_LIKELY),
    )


def test_feasible_scenario_requires_candidate_and_buffer() -> None:
    with pytest.raises(ValidationError):
        FeasibilityScenarioResult(
            scenario=FeasibilityScenario.LIKELY,
            solver_status=SolverRunStatus.OPTIMAL,
            candidate_id=None,
            buffer_minutes=None,
        )


def test_infeasible_scenario_rejects_candidate_data() -> None:
    with pytest.raises(ValidationError):
        FeasibilityScenarioResult(
            scenario=FeasibilityScenario.LIKELY,
            solver_status=SolverRunStatus.INFEASIBLE,
            candidate_id="candidate-001",
            buffer_minutes=60,
        )


def test_not_feasible_assessment_requires_null_likely_candidate() -> None:
    results = list(_all_results())
    results[1] = _result(FeasibilityScenario.LIKELY, SolverRunStatus.INFEASIBLE)
    with pytest.raises(ValidationError):
        FeasibilityAssessment(
            status=FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS,
            likely_candidate_id="candidate-001",
            scenario_results=tuple(results),
        )


def test_feasible_assessment_requires_likely_candidate() -> None:
    with pytest.raises(ValidationError):
        FeasibilityAssessment(
            status=FeasibilityStatus.FEASIBLE,
            likely_candidate_id=None,
            scenario_results=_all_results(),
        )


def test_scenario_results_require_canonical_order() -> None:
    results = list(_all_results())
    results[0], results[1] = results[1], results[0]
    with pytest.raises(ValidationError, match="canonical"):
        FeasibilityAssessment(
            status=FeasibilityStatus.FEASIBLE,
            likely_candidate_id="candidate-001",
            scenario_results=tuple(results),
        )
