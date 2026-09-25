"""Deterministic dependency graph utilities for workload analysis."""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
import heapq
from types import MappingProxyType

from packages.contracts.models import Task


class WorkloadGraphError(ValueError):
    """Base error for invalid workload graph semantics."""


class WorkloadDependencyError(WorkloadGraphError):
    """Raised when task dependency references are structurally invalid."""


class WorkloadCycleError(WorkloadGraphError):
    """Raised when dependency relations contain a directed cycle."""

    def __init__(self, cycle: tuple[str, ...]) -> None:
        self.cycle = cycle
        super().__init__(f"workload dependency cycle detected: {' -> '.join(cycle)}")


@dataclass(frozen=True, slots=True)
class DependencyGraph:
    """Canonical dependency mapping plus deterministic topological order."""

    dependencies: Mapping[str, tuple[str, ...]]
    topological_order: tuple[str, ...]


def build_dependency_graph(tasks: tuple[Task, ...]) -> DependencyGraph:
    """Validate dependencies and build a deterministic DAG representation."""

    task_ids = [task.task_id for task in tasks]
    if len(set(task_ids)) != len(task_ids):
        raise WorkloadDependencyError("task_id values must be unique")

    known = set(task_ids)
    dependencies: dict[str, tuple[str, ...]] = {}
    for task in tasks:
        deps = tuple(sorted(task.dependencies))
        if task.task_id in deps:
            raise WorkloadDependencyError(
                f"task {task.task_id!r} must not depend on itself"
            )
        if len(set(deps)) != len(deps):
            raise WorkloadDependencyError(
                f"task {task.task_id!r} dependencies must be unique"
            )
        missing = [dep for dep in deps if dep not in known]
        if missing:
            joined = ", ".join(missing)
            raise WorkloadDependencyError(
                f"task {task.task_id!r} references missing dependencies: {joined}"
            )
        dependencies[task.task_id] = deps

    order = _topological_order(dependencies)
    return DependencyGraph(
        dependencies=MappingProxyType(dict(dependencies)),
        topological_order=order,
    )


def required_task_closure(
    tasks: tuple[Task, ...],
    graph: DependencyGraph,
) -> tuple[str, ...]:
    """Return mandatory tasks plus every transitive prerequisite.

    The source `mandatory` flag is never mutated. Requiredness here is derived
    execution semantics only.
    """

    task_by_id = {task.task_id: task for task in tasks}
    if len(task_by_id) != len(tasks):
        raise WorkloadDependencyError("task_id values must be unique")

    graph_ids = set(graph.dependencies)
    task_ids = set(task_by_id)
    if task_ids != graph_ids:
        raise WorkloadDependencyError(
            "task set must match the dependency graph exactly"
        )

    for task_id, task in task_by_id.items():
        expected_dependencies = tuple(sorted(task.dependencies))
        if graph.dependencies[task_id] != expected_dependencies:
            raise WorkloadDependencyError(
                f"task {task_id!r} dependencies do not match the validated graph"
            )

    required = {task.task_id for task in tasks if task.mandatory}
    stack = sorted(required, reverse=True)
    while stack:
        task_id = stack.pop()
        for dependency in graph.dependencies[task_id]:
            if dependency not in required:
                required.add(dependency)
                stack.append(dependency)

    return tuple(
        task_id for task_id in graph.topological_order if task_id in required
    )


def _topological_order(
    dependencies: dict[str, tuple[str, ...]],
) -> tuple[str, ...]:
    indegree = {task_id: len(deps) for task_id, deps in dependencies.items()}
    dependents: dict[str, list[str]] = {task_id: [] for task_id in dependencies}
    for task_id, deps in dependencies.items():
        for dependency in deps:
            dependents[dependency].append(task_id)

    ready = [task_id for task_id, degree in indegree.items() if degree == 0]
    heapq.heapify(ready)
    order: list[str] = []

    while ready:
        task_id = heapq.heappop(ready)
        order.append(task_id)
        for dependent in sorted(dependents[task_id]):
            indegree[dependent] -= 1
            if indegree[dependent] == 0:
                heapq.heappush(ready, dependent)

    if len(order) != len(dependencies):
        cycle = _find_cycle(dependencies)
        raise WorkloadCycleError(cycle)
    return tuple(order)


def _find_cycle(dependencies: dict[str, tuple[str, ...]]) -> tuple[str, ...]:
    """Return one deterministic cycle path without recursion-limit dependence."""

    unresolved = set(dependencies)
    # Re-run Kahn elimination only to isolate the cyclic remainder used for
    # deterministic path reconstruction.
    indegree = {task_id: len(deps) for task_id, deps in dependencies.items()}
    dependents: dict[str, list[str]] = {task_id: [] for task_id in dependencies}
    for task_id, deps in dependencies.items():
        for dependency in deps:
            dependents[dependency].append(task_id)

    ready = [task_id for task_id, degree in indegree.items() if degree == 0]
    heapq.heapify(ready)
    while ready:
        task_id = heapq.heappop(ready)
        unresolved.discard(task_id)
        for dependent in sorted(dependents[task_id]):
            indegree[dependent] -= 1
            if indegree[dependent] == 0:
                heapq.heappush(ready, dependent)

    if not unresolved:
        raise RuntimeError("cycle expected but cyclic remainder is empty")

    current = min(unresolved)
    path: list[str] = []
    positions: dict[str, int] = {}

    while current not in positions:
        positions[current] = len(path)
        path.append(current)
        candidates = [dep for dep in dependencies[current] if dep in unresolved]
        if not candidates:
            raise RuntimeError(
                "cycle remainder contains a node without cyclic dependency"
            )
        current = min(candidates)

    start = positions[current]
    return tuple(path[start:] + [current])
