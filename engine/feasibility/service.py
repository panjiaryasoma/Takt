"""Block 4 deterministic feasibility classification over Block 2/3 authorities."""

from __future__ import annotations

from pydantic import ValidationError

from engine.availability.models import AvailabilityResult
from engine.feasibility.models import (
    FeasibilityAssessment,
    FeasibilityRun,
    FeasibilityScenario,
    FeasibilityScenarioResult,
)
from engine.feasibility.scenarios import SCENARIO_ORDER, analyze_scenario
from engine.scheduler import (
    SolverConfig,
    SolverInputError,
    SolverResult,
    SolverRunStatus,
    rank_candidate_allocations,
    solve_candidate_allocations,
)
from engine.workload import analyze_workload
from engine.workload.graph import WorkloadGraphError
from packages.contracts.enums import FeasibilityStatus
from packages.contracts.workload import WorkloadAnalysis, WorkloadInput


class FeasibilityInputError(ValueError):
    """Raised when source/scenario input cannot satisfy Block 2/3 boundaries."""


class FeasibilityInvariantError(RuntimeError):
    """Raised when known scenario facts violate frozen feasibility invariants."""


class FeasibilityExecutionError(RuntimeError):
    """Raised when the underlying scheduling engine fails to execute correctly."""


class FeasibilityIndeterminateError(RuntimeError):
    """Raised when UNKNOWN occurs on the active classification decision branch."""


def assess_feasibility(
    availability: AvailabilityResult,
    workload_input: WorkloadInput,
    config: SolverConfig,
) -> FeasibilityAssessment:
    """Compatibility API returning only the frozen Block 4 assessment."""

    return assess_feasibility_run(availability, workload_input, config).assessment


def assess_feasibility_run(
    availability: AvailabilityResult,
    workload_input: WorkloadInput,
    config: SolverConfig,
) -> FeasibilityRun:
    """Run all four scenarios once and preserve exact same-run Block 5 artifacts."""

    availability, workload_input, config, baseline = _validate_source_inputs(
        availability,
        workload_input,
        config,
    )

    results: list[FeasibilityScenarioResult] = []
    likely_solver_result: SolverResult | None = None
    for scenario in SCENARIO_ORDER:
        analysis = baseline if scenario is FeasibilityScenario.LIKELY else _analyze_scenario(
            workload_input,
            scenario,
        )
        scenario_result, solver_result = _solve_scenario(
            availability,
            analysis,
            config,
            scenario,
        )
        results.append(scenario_result)
        if scenario is FeasibilityScenario.LIKELY:
            likely_solver_result = solver_result

    if likely_solver_result is None:
        raise FeasibilityInvariantError("LIKELY solver result was not captured")

    ordered_results = tuple(results)
    has_truly_optional = bool(
        {task.task_id for task in baseline.tasks} - set(baseline.required_task_ids)
    )
    _validate_monotonicity(ordered_results)
    _validate_full_scope_equivalence(ordered_results, has_truly_optional)
    status = _classify(ordered_results)

    likely = ordered_results[1]
    likely_candidate_id = None
    if status is not FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS:
        likely_candidate_id = likely.candidate_id

    assessment = FeasibilityAssessment(
        status=status,
        likely_candidate_id=likely_candidate_id,
        scenario_results=ordered_results,
        reason_codes=_reason_codes(ordered_results),
        tradeoff_codes=_tradeoff_codes(ordered_results, has_truly_optional),
        sensitivity_codes=_sensitivity_codes(ordered_results),
        assumptions=baseline.assumptions,
    )
    return FeasibilityRun(
        assessment=assessment,
        likely_solver_result=likely_solver_result,
        baseline_workload_analysis=baseline,
    )


def _validate_source_inputs(
    availability: AvailabilityResult,
    workload_input: WorkloadInput,
    config: SolverConfig,
) -> tuple[AvailabilityResult, WorkloadInput, SolverConfig, WorkloadAnalysis]:
    try:
        clean_availability = AvailabilityResult.model_validate(
            availability.model_dump(mode="python", warnings=False)
        )
        clean_workload = WorkloadInput.model_validate(
            workload_input.model_dump(mode="python", warnings=False)
        )
        clean_config = SolverConfig.model_validate(
            config.model_dump(mode="python", warnings=False)
        )
        baseline = analyze_workload(clean_workload)
    except (ValidationError, WorkloadGraphError, ValueError) as exc:
        raise FeasibilityInputError(f"invalid feasibility input: {exc}") from exc
    except RuntimeError as exc:
        raise FeasibilityExecutionError(f"workload analysis execution failed: {exc}") from exc
    return clean_availability, clean_workload, clean_config, baseline


def _analyze_scenario(
    workload_input: WorkloadInput,
    scenario: FeasibilityScenario,
) -> WorkloadAnalysis:
    try:
        return analyze_scenario(workload_input, scenario)
    except (ValidationError, WorkloadGraphError, ValueError) as exc:
        raise FeasibilityInputError(
            f"invalid {scenario.value} feasibility scenario: {exc}"
        ) from exc
    except RuntimeError as exc:
        raise FeasibilityExecutionError(
            f"{scenario.value} workload analysis execution failed: {exc}"
        ) from exc


def _solve_scenario(
    availability: AvailabilityResult,
    workload: WorkloadAnalysis,
    config: SolverConfig,
    scenario: FeasibilityScenario,
) -> tuple[FeasibilityScenarioResult, SolverResult]:
    try:
        raw = solve_candidate_allocations(availability, workload, config)
    except SolverInputError as exc:
        raise FeasibilityInputError(
            f"{scenario.value} solver rejected feasibility input: {exc}"
        ) from exc
    except RuntimeError as exc:
        raise FeasibilityExecutionError(
            f"{scenario.value} solver execution failed: {exc}"
        ) from exc

    try:
        result = SolverResult.model_validate(raw.model_dump(mode="python", warnings=False))
    except (AttributeError, ValidationError) as exc:
        raise FeasibilityExecutionError(
            f"{scenario.value} solver returned an invalid result shape"
        ) from exc

    if _is_feasible(result.status):
        ranked = rank_candidate_allocations(result.candidate_allocations)
        if not ranked:
            raise FeasibilityInvariantError(
                f"{scenario.value} solver produced no recommendable candidate "
                "after hard-constraint filtering"
            )
        candidate = ranked[0]
        scenario_result = FeasibilityScenarioResult(
            scenario=scenario,
            solver_status=result.status,
            candidate_id=candidate.candidate_id,
            buffer_minutes=candidate.buffer_minutes,
            solver_reason_codes=result.reason_codes,
        )
        return scenario_result, result

    scenario_result = FeasibilityScenarioResult(
        scenario=scenario,
        solver_status=result.status,
        candidate_id=None,
        buffer_minutes=None,
        solver_reason_codes=result.reason_codes,
    )
    return scenario_result, result


def _validate_monotonicity(
    results: tuple[FeasibilityScenarioResult, ...],
) -> None:
    by_scenario = {item.scenario: item for item in results}
    dominance_pairs = (
        (FeasibilityScenario.MIN, FeasibilityScenario.LIKELY),
        (FeasibilityScenario.LIKELY, FeasibilityScenario.MAX),
        (FeasibilityScenario.MIN, FeasibilityScenario.MAX),
        (FeasibilityScenario.LIKELY, FeasibilityScenario.FULL_SCOPE_LIKELY),
        (FeasibilityScenario.MIN, FeasibilityScenario.FULL_SCOPE_LIKELY),
    )
    for easier, harder in dominance_pairs:
        easier_status = by_scenario[easier].solver_status
        harder_status = by_scenario[harder].solver_status
        if easier_status is SolverRunStatus.INFEASIBLE and _is_feasible(harder_status):
            raise FeasibilityInvariantError(
                f"scenario monotonicity violated: {harder.value} feasible while "
                f"{easier.value} infeasible"
            )


def _validate_full_scope_equivalence(
    results: tuple[FeasibilityScenarioResult, ...],
    has_truly_optional: bool,
) -> None:
    if has_truly_optional:
        return
    likely = results[1]
    full_scope = results[3]
    if (
        likely.solver_status != full_scope.solver_status
        or likely.candidate_id != full_scope.candidate_id
        or likely.buffer_minutes != full_scope.buffer_minutes
        or likely.solver_reason_codes != full_scope.solver_reason_codes
    ):
        raise FeasibilityInvariantError(
            "FULL_SCOPE_LIKELY must equal LIKELY when no truly optional task exists"
        )


def _classify(
    results: tuple[FeasibilityScenarioResult, ...],
) -> FeasibilityStatus:
    by_scenario = {item.scenario: item for item in results}
    likely = by_scenario[FeasibilityScenario.LIKELY].solver_status
    maximum = by_scenario[FeasibilityScenario.MAX].solver_status
    full_scope = by_scenario[FeasibilityScenario.FULL_SCOPE_LIKELY].solver_status

    if likely is SolverRunStatus.UNKNOWN:
        raise FeasibilityIndeterminateError("LIKELY scenario returned UNKNOWN")
    if likely is SolverRunStatus.INFEASIBLE:
        return FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS

    if maximum is SolverRunStatus.UNKNOWN:
        raise FeasibilityIndeterminateError(
            "MAX scenario returned UNKNOWN while LIKELY is feasible"
        )
    if maximum is SolverRunStatus.INFEASIBLE:
        return FeasibilityStatus.TIGHT_CAPACITY

    if full_scope is SolverRunStatus.UNKNOWN:
        raise FeasibilityIndeterminateError(
            "FULL_SCOPE_LIKELY returned UNKNOWN while LIKELY and MAX are feasible"
        )
    if full_scope is SolverRunStatus.INFEASIBLE:
        return FeasibilityStatus.FEASIBLE_WITH_TRADEOFFS
    return FeasibilityStatus.FEASIBLE


def _reason_codes(
    results: tuple[FeasibilityScenarioResult, ...],
) -> tuple[str, ...]:
    by_scenario = {item.scenario: item.solver_status for item in results}
    codes: list[str] = []
    if by_scenario[FeasibilityScenario.LIKELY] is SolverRunStatus.INFEASIBLE:
        codes.append("REQUIRED_LIKELY_INFEASIBLE")
    if by_scenario[FeasibilityScenario.MAX] is SolverRunStatus.INFEASIBLE:
        codes.append("REQUIRED_MAX_INFEASIBLE")
    if by_scenario[FeasibilityScenario.FULL_SCOPE_LIKELY] is SolverRunStatus.INFEASIBLE:
        codes.append("FULL_SCOPE_LIKELY_INFEASIBLE")
    if by_scenario[FeasibilityScenario.FULL_SCOPE_LIKELY] is SolverRunStatus.UNKNOWN:
        codes.append("FULL_SCOPE_LIKELY_SCENARIO_UNKNOWN")
    if all(
        _is_feasible(by_scenario[scenario])
        for scenario in (
            FeasibilityScenario.MIN,
            FeasibilityScenario.LIKELY,
            FeasibilityScenario.MAX,
        )
    ):
        codes.append("ALL_REQUIRED_SCENARIOS_FEASIBLE")
    if _is_feasible(by_scenario[FeasibilityScenario.FULL_SCOPE_LIKELY]):
        codes.append("FULL_SCOPE_LIKELY_FEASIBLE")
    return tuple(codes)


def _tradeoff_codes(
    results: tuple[FeasibilityScenarioResult, ...],
    has_truly_optional: bool,
) -> tuple[str, ...]:
    likely = results[1]
    full_scope = results[3]
    if (
        has_truly_optional
        and _is_feasible(likely.solver_status)
        and full_scope.solver_status is SolverRunStatus.INFEASIBLE
    ):
        return ("OPTIONAL_SCOPE_DOES_NOT_FIT",)
    return ()


def _sensitivity_codes(
    results: tuple[FeasibilityScenarioResult, ...],
) -> tuple[str, ...]:
    by_scenario = {item.scenario: item.solver_status for item in results}
    codes: list[str] = []
    minimum = by_scenario[FeasibilityScenario.MIN]
    likely = by_scenario[FeasibilityScenario.LIKELY]
    maximum = by_scenario[FeasibilityScenario.MAX]

    if _is_feasible(minimum):
        codes.append("MINIMUM_EFFORT_SCENARIO_FEASIBLE")
    elif minimum is SolverRunStatus.UNKNOWN:
        codes.append("MIN_SCENARIO_UNKNOWN")

    if likely is SolverRunStatus.INFEASIBLE:
        codes.append("LIKELY_EFFORT_SCENARIO_INFEASIBLE")

    if _is_feasible(likely) and maximum is SolverRunStatus.INFEASIBLE:
        codes.append("EFFORT_OVERRUN_BREAKS_PLAN")
    if _is_feasible(maximum):
        codes.append("MAX_EFFORT_SCENARIO_FEASIBLE")
    elif maximum is SolverRunStatus.UNKNOWN:
        codes.append("MAX_SCENARIO_UNKNOWN")
    return tuple(codes)


def _is_feasible(status: SolverRunStatus) -> bool:
    return status in {SolverRunStatus.OPTIMAL, SolverRunStatus.FEASIBLE}
