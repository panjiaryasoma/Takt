"""Block 5 deterministic recommendation assembly over frozen Block 4 artifacts."""

from __future__ import annotations

from datetime import UTC

from pydantic import ValidationError

from engine.feasibility.models import FeasibilityScenario
from engine.recommendation.messages import (
    render_rationale,
    render_tradeoffs,
)
from engine.recommendation.models import (
    RecommendationAssembly,
    RecommendationBuildInput,
    RecommendationPayload,
    RecommendedNextWork,
    SuggestedWorkWindow,
)
from engine.scheduler.models import SolverRunStatus
from packages.contracts.enums import FeasibilityStatus, RecommendationAction
from packages.contracts.models import CandidateAllocation, Recommendation


class RecommendationInputError(ValueError):
    """Raised when the recommendation build boundary receives malformed input."""


class RecommendationInvariantError(RuntimeError):
    """Raised when valid Block 4 artifacts contradict one another."""


_FEASIBLE_SOLVER_STATUSES = {
    SolverRunStatus.OPTIMAL,
    SolverRunStatus.FEASIBLE,
}


_RECOMMENDATION_ACTIONS = (
    RecommendationAction.ACCEPT,
    RecommendationAction.EDIT_CONSTRAINTS,
    RecommendationAction.IGNORE,
)


_NO_RECOMMENDATION_ACTIONS = (
    RecommendationAction.EDIT_CONSTRAINTS,
    RecommendationAction.IGNORE,
)


def build_recommendation(data: RecommendationBuildInput) -> RecommendationAssembly:
    """Assemble advisory recommendation without solving, reclassifying, or mutating."""

    clean = _revalidate_input(data)
    run = clean.feasibility_run
    assessment = run.assessment
    baseline = run.baseline_workload_analysis
    solver_result = run.likely_solver_result
    likely = _likely_scenario(assessment.scenario_results)

    _validate_run_consistency(run, likely)

    rationale = render_rationale(
        assessment.reason_codes,
        assessment.sensitivity_codes,
    )
    tradeoffs = render_tradeoffs(assessment.tradeoff_codes)

    if assessment.status is FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS:
        try:
            return RecommendationAssembly(
                recommendation_payload=None,
                primary_candidate_id=None,
                alternative_candidate_ids=(),
                allowed_actions=_NO_RECOMMENDATION_ACTIONS,
                source_feasibility_status=assessment.status,
                source_competition_id=clean.trace_context.competition_id,
                source_report_version=clean.trace_context.report_version,
            )
        except ValidationError as exc:
            raise RecommendationInvariantError(
                "recommendation assembly contradicts feasibility state"
            ) from exc

    candidate = _primary_candidate(solver_result.candidate_allocations)
    _validate_primary_candidate(candidate, assessment.likely_candidate_id, likely)
    task_by_id = _task_index(baseline.tasks)
    _validate_candidate_task_references(candidate, task_by_id)

    windows = _suggested_windows(candidate)
    next_work = _recommended_next_work(windows, task_by_id)
    try:
        payload = RecommendationPayload(
            recommended_candidate_id=candidate.candidate_id,
            recommended_next_work=next_work,
            suggested_windows=windows,
            alternatives=(),
            rationale=rationale,
            tradeoffs=tradeoffs,
            assumptions=assessment.assumptions,
        )
    except ValidationError as exc:
        raise RecommendationInvariantError(
            "recommendation payload contradicts feasibility evidence"
        ) from exc

    try:
        return RecommendationAssembly(
            recommendation_payload=payload,
            primary_candidate_id=candidate.candidate_id,
            alternative_candidate_ids=(),
            allowed_actions=_RECOMMENDATION_ACTIONS,
            source_feasibility_status=assessment.status,
            source_competition_id=clean.trace_context.competition_id,
            source_report_version=clean.trace_context.report_version,
        )
    except ValidationError as exc:
        raise RecommendationInvariantError(
            "recommendation assembly contradicts feasibility state"
        ) from exc


def materialize_public_recommendation(payload: RecommendationPayload) -> Recommendation:
    """Create a fresh loose public DTO from a revalidated immutable payload."""

    try:
        if not isinstance(payload, RecommendationPayload):
            raise TypeError("payload must be RecommendationPayload")
        clean = RecommendationPayload.model_validate(
            payload.model_dump(mode="python", warnings=False)
        )
    except (AttributeError, TypeError, ValidationError, ValueError) as exc:
        raise RecommendationInputError(
            f"invalid recommendation payload for materialization: {exc}"
        ) from exc

    next_work = None
    if clean.recommended_next_work is not None:
        next_work = clean.recommended_next_work.model_dump(mode="python")

    return Recommendation(
        recommended_candidate_id=clean.recommended_candidate_id,
        recommended_next_work=next_work,
        suggested_windows=[item.model_dump(mode="python") for item in clean.suggested_windows],
        alternatives=list(clean.alternatives),
        rationale=list(clean.rationale),
        tradeoffs=list(clean.tradeoffs),
        assumptions=[item.model_dump(mode="python") for item in clean.assumptions],
    )


def _revalidate_input(data: RecommendationBuildInput) -> RecommendationBuildInput:
    try:
        if not isinstance(data, RecommendationBuildInput):
            raise TypeError("data must be RecommendationBuildInput")
        return RecommendationBuildInput.model_validate(
            data.model_dump(mode="python", warnings=False)
        )
    except (AttributeError, TypeError, ValidationError, ValueError) as exc:
        raise RecommendationInputError(f"invalid recommendation input: {exc}") from exc


def _likely_scenario(scenario_results):
    matches = [
        item
        for item in scenario_results
        if item.scenario is FeasibilityScenario.LIKELY
    ]
    if len(matches) != 1:
        raise RecommendationInvariantError(
            "feasibility assessment must contain exactly one LIKELY scenario"
        )
    return matches[0]


def _validate_run_consistency(run, likely) -> None:
    assessment = run.assessment
    solver_result = run.likely_solver_result
    baseline = run.baseline_workload_analysis

    if baseline.assumptions != assessment.assumptions:
        raise RecommendationInvariantError(
            "baseline workload assumptions do not match feasibility assessment assumptions"
        )
    if solver_result.status is not likely.solver_status:
        raise RecommendationInvariantError(
            "LIKELY solver status does not match feasibility assessment"
        )
    if solver_result.reason_codes != likely.solver_reason_codes:
        raise RecommendationInvariantError(
            "LIKELY solver reason codes do not match feasibility assessment"
        )

    not_feasible = (
        assessment.status
        is FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS
    )
    if not_feasible:
        if solver_result.status is not SolverRunStatus.INFEASIBLE:
            raise RecommendationInvariantError(
                "not-feasible assessment requires an infeasible LIKELY solver result"
            )
        if solver_result.candidate_allocations:
            raise RecommendationInvariantError(
                "not-feasible LIKELY solver result must not contain candidates"
            )
        return

    if solver_result.status not in _FEASIBLE_SOLVER_STATUSES:
        raise RecommendationInvariantError(
            "recommendable assessment requires a feasible LIKELY solver result"
        )
    if len(solver_result.candidate_allocations) != 1:
        raise RecommendationInvariantError(
            "Block 5 MVP requires exactly one feasible LIKELY candidate"
        )


def _primary_candidate(
    candidates: tuple[CandidateAllocation, ...],
) -> CandidateAllocation:
    if len(candidates) != 1:
        raise RecommendationInvariantError(
            "Block 5 MVP requires exactly one primary LIKELY candidate"
        )
    return candidates[0]


def _validate_primary_candidate(candidate, likely_candidate_id, likely) -> None:
    if likely_candidate_id is None:
        raise RecommendationInvariantError(
            "recommendable assessment must expose a LIKELY candidate ID"
        )
    if candidate.candidate_id != likely_candidate_id:
        raise RecommendationInvariantError(
            "LIKELY solver candidate ID does not match feasibility assessment"
        )
    if likely.candidate_id != candidate.candidate_id:
        raise RecommendationInvariantError(
            "LIKELY scenario candidate ID does not match exact solver candidate"
        )
    if likely.buffer_minutes != candidate.buffer_minutes:
        raise RecommendationInvariantError(
            "LIKELY candidate buffer does not match feasibility assessment"
        )
    if candidate.hard_constraint_violations or not candidate.is_recommendable:
        raise RecommendationInvariantError(
            "primary recommendation candidate contains hard-constraint violations"
        )


def _task_index(tasks):
    result = {task.task_id: task for task in tasks}
    if len(result) != len(tasks):
        raise RecommendationInvariantError(
            "baseline workload contains duplicate task IDs"
        )
    return result


def _validate_candidate_task_references(candidate, task_by_id) -> None:
    unknown = sorted(
        {
            block.task_id
            for block in candidate.work_blocks
            if block.task_id not in task_by_id
        }
    )
    if unknown:
        joined = ", ".join(unknown)
        raise RecommendationInvariantError(
            f"candidate work blocks reference unknown workload task IDs: {joined}"
        )


def _suggested_windows(
    candidate: CandidateAllocation,
) -> tuple[SuggestedWorkWindow, ...]:
    ordered = sorted(
        candidate.work_blocks,
        key=lambda item: (
            item.start.astimezone(UTC),
            item.task_id,
            item.end.astimezone(UTC),
        ),
    )
    return tuple(
        SuggestedWorkWindow(
            task_id=item.task_id,
            start=item.start,
            end=item.end,
            allocated_minutes=item.allocated_minutes,
            availability_source=item.availability_source,
        )
        for item in ordered
    )


def _recommended_next_work(windows, task_by_id) -> RecommendedNextWork | None:
    if not windows:
        return None
    first = windows[0]
    task = task_by_id[first.task_id]
    return RecommendedNextWork(
        task_id=first.task_id,
        task_name=task.name,
        start=first.start,
        end=first.end,
        allocated_minutes=first.allocated_minutes,
        availability_source=first.availability_source,
    )
