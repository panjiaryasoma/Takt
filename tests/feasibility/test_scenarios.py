from __future__ import annotations

import json
from pathlib import Path

from engine.feasibility.models import FeasibilityScenario
from engine.feasibility.scenarios import analyze_scenario, build_scenario_input
from engine.workload import analyze_workload
from packages.contracts.workload import WorkloadInput


def _fixture() -> WorkloadInput:
    payload = json.loads(
        Path("tests/fixtures/feasibility/feasibility_001.json").read_text(encoding="utf-8")
    )
    return WorkloadInput.model_validate(payload)


def test_min_scenario_uses_source_min_as_likely() -> None:
    source = _fixture()
    scenario = build_scenario_input(source, FeasibilityScenario.MIN)
    assert [task.effort_likely_minutes for task in scenario.tasks] == [60, 60]


def test_max_scenario_uses_source_max_as_likely() -> None:
    source = _fixture()
    scenario = build_scenario_input(source, FeasibilityScenario.MAX)
    assert [task.effort_likely_minutes for task in scenario.tasks] == [180, 120]


def test_full_scope_marks_every_cloned_task_mandatory() -> None:
    source = _fixture()
    scenario = build_scenario_input(source, FeasibilityScenario.FULL_SCOPE_LIKELY)
    assert all(task.mandatory for task in scenario.tasks)
    assert [task.effort_likely_minutes for task in scenario.tasks] == [120, 120]


def test_scenario_construction_does_not_mutate_source() -> None:
    source = _fixture()
    before = source.model_dump(mode="python")
    for scenario in FeasibilityScenario:
        build_scenario_input(source, scenario)
    assert source.model_dump(mode="python") == before


def test_reanalysis_starts_from_workload_input_without_assumption_duplication() -> None:
    source = _fixture()
    baseline = analyze_workload(source)
    maximum = analyze_scenario(source, FeasibilityScenario.MAX)
    assert maximum.assumptions == baseline.assumptions
    assert len(maximum.assumptions) == 2


def test_full_scope_requiredness_is_recomputed_by_block_2() -> None:
    source = _fixture()
    analysis = analyze_scenario(source, FeasibilityScenario.FULL_SCOPE_LIKELY)
    assert analysis.required_task_ids == ("core", "optional")
