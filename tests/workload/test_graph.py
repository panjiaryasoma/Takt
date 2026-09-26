import pytest

from engine.workload.graph import (
    WorkloadCycleError,
    WorkloadDependencyError,
    build_dependency_graph,
    required_task_closure,
)
from packages.contracts.models import Task


def task(task_id, *, mandatory=False, dependencies=()):
    return Task(
        task_id=task_id,
        name=task_id,
        mandatory=mandatory,
        dependencies=dependencies,
        effort_min_minutes=10,
        effort_likely_minutes=20,
        effort_max_minutes=30,
        assumptions=(),
    )


def test_duplicate_task_id_is_rejected() -> None:
    with pytest.raises(WorkloadDependencyError, match="unique"):
        build_dependency_graph((task("A"), task("A")))


def test_missing_dependency_target_is_rejected() -> None:
    with pytest.raises(WorkloadDependencyError, match="missing"):
        build_dependency_graph((task("A", dependencies=("X",)),))


def test_simple_chain_has_dependency_first_topological_order() -> None:
    graph = build_dependency_graph(
        (
            task("C", dependencies=("B",)),
            task("A"),
            task("B", dependencies=("A",)),
        )
    )
    assert graph.topological_order == ("A", "B", "C")


def test_independent_tie_break_is_task_id_ascending() -> None:
    graph = build_dependency_graph((task("B"), task("A"), task("C", dependencies=("A",))))
    assert graph.topological_order == ("A", "B", "C")


def test_cycle_is_rejected_with_deterministic_cycle_path() -> None:
    with pytest.raises(WorkloadCycleError) as exc_info:
        build_dependency_graph(
            (
                task("A", dependencies=("B",)),
                task("B", dependencies=("C",)),
                task("C", dependencies=("A",)),
            )
        )
    assert exc_info.value.cycle == ("A", "B", "C", "A")


def test_optional_prerequisite_of_mandatory_becomes_derived_required() -> None:
    tasks = (
        task("A", mandatory=False),
        task("B", mandatory=True, dependencies=("A",)),
    )
    graph = build_dependency_graph(tasks)
    assert required_task_closure(tasks, graph) == ("A", "B")
    assert tasks[0].mandatory is False


def test_transitive_required_closure_is_computed() -> None:
    tasks = (
        task("A"),
        task("B", dependencies=("A",)),
        task("C", mandatory=True, dependencies=("B",)),
        task("Z"),
    )
    graph = build_dependency_graph(tasks)
    assert required_task_closure(tasks, graph) == ("A", "B", "C")


def test_large_cycle_raises_domain_error_without_recursion_failure() -> None:
    size = 1200
    tasks = tuple(
        task(
            f"T{index:04d}",
            dependencies=(f"T{(index + 1) % size:04d}",),
        )
        for index in range(size)
    )
    with pytest.raises(WorkloadCycleError):
        build_dependency_graph(tasks)


def test_validated_dependency_mapping_is_immutable() -> None:
    graph = build_dependency_graph(
        (
            task("A"),
            task("B", mandatory=True, dependencies=("A",)),
        )
    )

    with pytest.raises(TypeError):
        graph.dependencies["B"] = ()


def test_required_closure_remains_invariant_after_graph_construction() -> None:
    tasks = (
        task("A"),
        task("B", mandatory=True, dependencies=("A",)),
    )
    graph = build_dependency_graph(tasks)
    before = required_task_closure(tasks, graph)

    with pytest.raises(TypeError):
        graph.dependencies["B"] = ()

    after = required_task_closure(tasks, graph)
    assert before == after == ("A", "B")


def test_required_closure_rejects_task_graph_dependency_mismatch() -> None:
    graph = build_dependency_graph(
        (
            task("A"),
            task("B", mandatory=True, dependencies=("A",)),
        )
    )
    mismatched_tasks = (task("A"), task("B", mandatory=True))

    with pytest.raises(WorkloadDependencyError, match="do not match"):
        required_task_closure(mismatched_tasks, graph)
