"""Deterministic workload what-if construction for Block 4 feasibility."""

from __future__ import annotations

from engine.feasibility.models import FeasibilityScenario
from engine.workload import analyze_workload
from packages.contracts.models import Task
from packages.contracts.workload import WorkloadAnalysis, WorkloadInput

SCENARIO_ORDER = (
    FeasibilityScenario.MIN,
    FeasibilityScenario.LIKELY,
    FeasibilityScenario.MAX,
    FeasibilityScenario.FULL_SCOPE_LIKELY,
)


def build_scenario_input(
    source: WorkloadInput,
    scenario: FeasibilityScenario,
) -> WorkloadInput:
    """Clone source facts into one what-if scenario without mutating the source."""

    source = WorkloadInput.model_validate(source.model_dump(mode="python", warnings=False))
    tasks = tuple(_clone_task(task, scenario) for task in source.tasks)
    return WorkloadInput(tasks=tasks, assumptions=source.assumptions)


def analyze_scenario(
    source: WorkloadInput,
    scenario: FeasibilityScenario,
) -> WorkloadAnalysis:
    """Construct and analyze one scenario through the Block 2 authority."""

    return analyze_workload(build_scenario_input(source, scenario))


def _clone_task(task: Task, scenario: FeasibilityScenario) -> Task:
    payload = task.model_dump(mode="python")
    if scenario is FeasibilityScenario.MIN:
        payload["effort_likely_minutes"] = task.effort_min_minutes
    elif scenario is FeasibilityScenario.MAX:
        payload["effort_likely_minutes"] = task.effort_max_minutes
    elif scenario is FeasibilityScenario.FULL_SCOPE_LIKELY:
        payload["mandatory"] = True
    return Task.model_validate(payload)
