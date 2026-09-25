"""Workload analysis without scheduling or feasibility decisions."""

from __future__ import annotations

from packages.contracts.models import Task
from packages.contracts.workload import (
    EffortRange,
    WorkloadAnalysis,
    WorkloadAssumption,
    WorkloadInput,
)

from engine.workload.graph import build_dependency_graph, required_task_closure


def analyze_workload(data: WorkloadInput) -> WorkloadAnalysis:
    """Validate workload semantics and produce deterministic derived analysis."""

    data = WorkloadInput.model_validate(data.model_dump(mode="python", warnings=False))
    tasks = _canonical_tasks(data.tasks)
    graph = build_dependency_graph(tasks)
    required_task_ids = required_task_closure(tasks, graph)
    required_set = set(required_task_ids)

    task_ids = {task.task_id for task in tasks}
    for assumption in data.assumptions:
        if assumption.task_id is not None and assumption.task_id not in task_ids:
            raise ValueError(
                f"workload assumption references unknown task_id {assumption.task_id!r}"
            )

    declared_mandatory = tuple(task for task in tasks if task.mandatory)
    required = tuple(task for task in tasks if task.task_id in required_set)
    optional = tuple(task for task in tasks if task.task_id not in required_set)

    assumptions = _canonical_assumptions(tasks, data.assumptions)

    return WorkloadAnalysis(
        tasks=tasks,
        topological_order=graph.topological_order,
        required_task_ids=required_task_ids,
        declared_mandatory_effort=_sum_effort(declared_mandatory),
        required_effort=_sum_effort(required),
        optional_effort=_sum_effort(optional),
        assumptions=assumptions,
    )


def _canonical_tasks(tasks: tuple[Task, ...]) -> tuple[Task, ...]:
    canonical: list[Task] = []
    for task in tasks:
        payload = task.model_dump(mode="python")
        payload["dependencies"] = tuple(sorted(payload["dependencies"]))
        payload["assumptions"] = tuple(sorted(payload["assumptions"]))
        canonical.append(Task.model_validate(payload))
    return tuple(sorted(canonical, key=lambda task: task.task_id))


def _canonical_assumptions(
    tasks: tuple[Task, ...],
    explicit: tuple[WorkloadAssumption, ...],
) -> tuple[WorkloadAssumption, ...]:
    combined = list(explicit)
    for task in tasks:
        combined.extend(
            WorkloadAssumption(task_id=task.task_id, description=description)
            for description in task.assumptions
        )
    return tuple(
        sorted(
            combined,
            key=lambda item: (item.task_id or "", item.description),
        )
    )


def _sum_effort(tasks: tuple[Task, ...]) -> EffortRange:
    return EffortRange(
        min_minutes=sum(task.effort_min_minutes for task in tasks),
        likely_minutes=sum(task.effort_likely_minutes for task in tasks),
        max_minutes=sum(task.effort_max_minutes for task in tasks),
    )
