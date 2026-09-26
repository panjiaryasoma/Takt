import pytest
from pydantic import ValidationError

from engine.workload import analyze_workload
from engine.workload.graph import WorkloadDependencyError
from packages.contracts.models import Task
from packages.contracts.workload import WorkloadAssumption, WorkloadInput


def task(
    task_id,
    *,
    mandatory=False,
    dependencies=(),
    effort=(10, 20, 30),
    assumptions=(),
):
    return Task(
        task_id=task_id,
        name=f"Task {task_id}",
        mandatory=mandatory,
        dependencies=dependencies,
        effort_min_minutes=effort[0],
        effort_likely_minutes=effort[1],
        effort_max_minutes=effort[2],
        assumptions=assumptions,
    )


def test_mandatory_and_optional_classification_is_preserved() -> None:
    analysis = analyze_workload(
        WorkloadInput(tasks=(task("A", mandatory=True), task("B", mandatory=False)))
    )
    by_id = {item.task_id: item for item in analysis.tasks}
    assert by_id["A"].mandatory is True
    assert by_id["B"].mandatory is False
    assert analysis.required_task_ids == ("A",)


def test_effort_totals_keep_min_likely_max_ranges() -> None:
    analysis = analyze_workload(
        WorkloadInput(
            tasks=(
                task("A", mandatory=True, effort=(60, 90, 120)),
                task("B", mandatory=True, effort=(120, 180, 240)),
            )
        )
    )
    assert analysis.required_effort.model_dump() == {
        "min_minutes": 180,
        "likely_minutes": 270,
        "max_minutes": 360,
    }


def test_required_effort_includes_optional_prerequisite() -> None:
    analysis = analyze_workload(
        WorkloadInput(
            tasks=(
                task("A", effort=(60, 90, 120)),
                task(
                    "B",
                    mandatory=True,
                    dependencies=("A",),
                    effort=(120, 180, 240),
                ),
            )
        )
    )
    assert analysis.declared_mandatory_effort.likely_minutes == 180
    assert analysis.required_effort.likely_minutes == 270
    assert analysis.optional_effort.likely_minutes == 0


def test_remaining_optional_effort_excludes_required_closure() -> None:
    analysis = analyze_workload(
        WorkloadInput(
            tasks=(
                task("A"),
                task("B", mandatory=True, dependencies=("A",)),
                task("C", effort=(40, 50, 60)),
            )
        )
    )
    assert analysis.optional_effort.model_dump() == {
        "min_minutes": 40,
        "likely_minutes": 50,
        "max_minutes": 60,
    }


def test_task_and_global_assumptions_survive_analysis() -> None:
    analysis = analyze_workload(
        WorkloadInput(
            tasks=(task("A", assumptions=("API has no OAuth",)),),
            assumptions=(
                WorkloadAssumption(description="team size assumed to be two"),
            ),
        )
    )
    assert [(item.task_id, item.description) for item in analysis.assumptions] == [
        (None, "team size assumed to be two"),
        ("A", "API has no OAuth"),
    ]


def test_assumption_unknown_task_is_rejected() -> None:
    with pytest.raises(ValueError, match="unknown task_id"):
        analyze_workload(
            WorkloadInput(
                tasks=(task("A"),),
                assumptions=(
                    WorkloadAssumption(task_id="X", description="unknown"),
                ),
            )
        )


def test_same_semantics_different_input_order_has_identical_output() -> None:
    first = WorkloadInput(
        tasks=(
            task("B", dependencies=("A",)),
            task("A"),
            task("C"),
        )
    )
    second = WorkloadInput(
        tasks=(
            task("C"),
            task("A"),
            task("B", dependencies=("A",)),
        )
    )
    assert analyze_workload(first).model_dump() == analyze_workload(second).model_dump()


def test_dependency_order_is_canonicalized() -> None:
    analysis = analyze_workload(
        WorkloadInput(
            tasks=(
                task("A"),
                task("B"),
                task("C", dependencies=("B", "A")),
            )
        )
    )
    by_id = {item.task_id: item for item in analysis.tasks}
    assert by_id["C"].dependencies == ("A", "B")


def test_duplicate_task_id_fails_at_analysis_boundary() -> None:
    with pytest.raises(WorkloadDependencyError):
        analyze_workload(WorkloadInput(tasks=(task("A"), task("A"))))


def test_mutated_or_invalid_contract_cannot_cross_boundary() -> None:
    valid = task("A")
    payload = valid.model_dump()
    payload["mandatory"] = "true"
    unsafe_task = Task.model_construct(**payload)
    unsafe_input = WorkloadInput.model_construct(tasks=(unsafe_task,), assumptions=())

    with pytest.raises(ValidationError):
        analyze_workload(unsafe_input)


def test_fixture_end_to_end() -> None:
    import json
    from pathlib import Path

    fixture = Path("tests/fixtures/workload/workload_001.json")
    payload = json.loads(fixture.read_text(encoding="utf-8"))
    analysis = analyze_workload(WorkloadInput.model_validate(payload))

    assert analysis.topological_order == ("schema", "backend", "polish")
    assert analysis.required_task_ids == ("schema", "backend")
    assert analysis.required_effort.likely_minutes == 450
    assert analysis.optional_effort.likely_minutes == 90
