"""Domain conclusions and technical failures remain separate at the HTTP seam."""

from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient
from ortools.sat.python import cp_model

import apps.api.routes.plans as route
import apps.api.services.plan_evaluation as service
import engine.feasibility.service as feasibility
from apps.api.main import app
from packages.contracts import WorkloadInput
from tests.reliability.support import (
    PLAN_ENDPOINT,
    PRIVATE_SENTINEL,
    assert_public_failure,
    clock,
    domain_request,
    plan_request,
)
from tests.support.recovery_policy import load_recovery_policy, recovery_for

DOMAIN_CASES = [
    row
    for row in load_recovery_policy().values()
    if row["contract_key"] is None
    and row["scenario_id"] not in {"STALE_SUPERSEDED", "BASIS_UNCHANGED"}
]


def post_plan(monkeypatch, request):
    monkeypatch.setattr(
        route, "evaluate_plan", lambda value: service.evaluate_plan(value, clock=clock)
    )
    with TestClient(app) as client:
        return client.post(PLAN_ENDPOINT.split()[1], json=request.model_dump(mode="json"))


@pytest.mark.parametrize("case", DOMAIN_CASES, ids=lambda row: row["scenario_id"])
def test_exact_domain_state_and_accept_boundary(monkeypatch, case):
    solve = Mock(wraps=feasibility.solve_candidate_allocations)
    monkeypatch.setattr(feasibility, "solve_candidate_allocations", solve)
    response = post_plan(monkeypatch, domain_request(case["scenario_id"]))
    assert response.status_code == 200, response.text
    body = response.json()
    planning = body["planning"]
    actual = body["readiness"]["status"] if planning is None else planning["feasibility"]
    assert actual == case["expected_state"]
    assert recovery_for(case["scenario_id"]) == case["recovery_class"]
    if planning is None:
        assert body["basis"]["planning"] is None
        assert "ACCEPT" not in response.text
        solve.assert_not_called()
    else:
        assert body["readiness"]["status"] == "READY_TO_EVALUATE"
        assert body["basis"]["planning"] is not None
        if actual == "NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS":
            assert planning["candidates"] == []
            assert planning["recommendation"] is None
            assert planning["allowed_actions"] == ["EDIT_CONSTRAINTS", "IGNORE"]


def test_dependency_cycle_fails_input_validation_before_solver(monkeypatch):
    request = plan_request(effort_minutes=30)
    original = request.planning.workload.tasks[0]
    tasks = (
        original.model_copy(update={"task_id": "a", "dependencies": ("b",)}),
        original.model_copy(update={"task_id": "b", "dependencies": ("a",)}),
    )
    request = request.model_copy(
        update={
            "planning": request.planning.model_copy(
                update={
                    "workload": WorkloadInput(tasks=tasks),
                }
            )
        }
    )
    solve = Mock(side_effect=AssertionError("Cycle must fail before solver"))
    monkeypatch.setattr(feasibility, "solve_candidate_allocations", solve)
    response = post_plan(monkeypatch, request)
    assert_public_failure(response, PLAN_ENDPOINT, "PlanEvaluationInputError")
    solve.assert_not_called()


def test_cp_sat_unknown_preserves_indeterminate_and_deterministic_budget(monkeypatch):
    configurations = []

    def exhausted(solver, _model):
        configurations.append(
            (
                solver.parameters.num_search_workers,
                solver.parameters.random_seed,
                solver.parameters.max_deterministic_time,
            )
        )
        return cp_model.UNKNOWN

    monkeypatch.setattr(cp_model.CpSolver, "Solve", exhausted)
    response = post_plan(monkeypatch, plan_request(effort_minutes=60))
    assert_public_failure(response, PLAN_ENDPOINT, "PlanEvaluationIndeterminateError")
    assert configurations == [(1, 0, 10.0)] * 4
    assert "NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS" not in response.text
    assert recovery_for("SOLVER_UNKNOWN") == "EDIT_CONSTRAINTS"


@pytest.mark.parametrize(
    "stage,contract_key",
    [
        ("solver", "PlanEvaluationSolverExecutionError"),
        ("availability", "PlanEvaluationAvailabilityError"),
    ],
)
def test_execution_crash_is_technical_failure(monkeypatch, stage, contract_key):
    crash = Mock(side_effect=RuntimeError(PRIVATE_SENTINEL))
    solve = crash if stage == "solver" else Mock(wraps=feasibility.solve_candidate_allocations)
    monkeypatch.setattr(feasibility, "solve_candidate_allocations", solve)
    if stage == "availability":
        monkeypatch.setattr(service, "build_availability", crash)
    response = post_plan(monkeypatch, plan_request(effort_minutes=60))
    assert_public_failure(response, PLAN_ENDPOINT, contract_key)
    assert "NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS" not in response.text
    crash.assert_called_once()
    if stage == "availability":
        solve.assert_not_called()
