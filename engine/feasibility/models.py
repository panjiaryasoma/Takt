"""Internal derived models for Issue 3A Block 4 feasibility classification."""

from __future__ import annotations

from enum import StrEnum
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, StrictInt, StringConstraints, model_validator

from engine.scheduler.models import SolverResult, SolverRunStatus
from packages.contracts.enums import FeasibilityStatus
from packages.contracts.workload import WorkloadAnalysis, WorkloadAssumption

NonEmptyStr = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, strict=True),
]
NonNegativeStrictInt = Annotated[StrictInt, Field(ge=0)]


class FeasibilityModel(BaseModel):
    """Strict/frozen model for internal feasibility-derived state."""

    model_config = ConfigDict(extra="forbid", frozen=True, validate_default=True)


class FeasibilityScenario(StrEnum):
    MIN = "MIN"
    LIKELY = "LIKELY"
    MAX = "MAX"
    FULL_SCOPE_LIKELY = "FULL_SCOPE_LIKELY"


class FeasibilityScenarioResult(FeasibilityModel):
    scenario: FeasibilityScenario
    solver_status: SolverRunStatus
    candidate_id: NonEmptyStr | None = None
    buffer_minutes: NonNegativeStrictInt | None = None
    solver_reason_codes: tuple[NonEmptyStr, ...] = ()

    @model_validator(mode="after")
    def validate_solver_shape(self) -> FeasibilityScenarioResult:
        feasible = self.solver_status in {
            SolverRunStatus.OPTIMAL,
            SolverRunStatus.FEASIBLE,
        }
        if feasible:
            if self.candidate_id is None or self.buffer_minutes is None:
                raise ValueError(
                    "feasible scenario result requires candidate_id and buffer_minutes"
                )
        elif self.candidate_id is not None or self.buffer_minutes is not None:
            raise ValueError(
                "infeasible/unknown scenario result must not contain candidate data"
            )
        return self


class FeasibilityAssessment(FeasibilityModel):
    status: FeasibilityStatus
    likely_candidate_id: NonEmptyStr | None
    scenario_results: tuple[FeasibilityScenarioResult, ...]
    reason_codes: tuple[NonEmptyStr, ...] = ()
    tradeoff_codes: tuple[NonEmptyStr, ...] = ()
    sensitivity_codes: tuple[NonEmptyStr, ...] = ()
    assumptions: tuple[WorkloadAssumption, ...] = ()

    @model_validator(mode="after")
    def validate_assessment_shape(self) -> FeasibilityAssessment:
        expected_order = (
            FeasibilityScenario.MIN,
            FeasibilityScenario.LIKELY,
            FeasibilityScenario.MAX,
            FeasibilityScenario.FULL_SCOPE_LIKELY,
        )
        actual_order = tuple(item.scenario for item in self.scenario_results)
        if actual_order != expected_order:
            raise ValueError("scenario_results must use canonical MIN/LIKELY/MAX/FULL order")

        for name, codes in (
            ("reason_codes", self.reason_codes),
            ("tradeoff_codes", self.tradeoff_codes),
            ("sensitivity_codes", self.sensitivity_codes),
        ):
            if len(set(codes)) != len(codes):
                raise ValueError(f"{name} must not contain duplicate values")

        likely = self.scenario_results[1]
        likely_feasible = likely.solver_status in {
            SolverRunStatus.OPTIMAL,
            SolverRunStatus.FEASIBLE,
        }
        if self.status is FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS:
            if self.likely_candidate_id is not None:
                raise ValueError("not-feasible assessment must not expose a LIKELY candidate")
            if likely.solver_status is not SolverRunStatus.INFEASIBLE:
                raise ValueError("not-feasible assessment requires LIKELY to be infeasible")
        else:
            if self.likely_candidate_id is None:
                raise ValueError("feasible assessment status requires a LIKELY candidate")
            if not likely_feasible or likely.candidate_id != self.likely_candidate_id:
                raise ValueError("likely_candidate_id must match the feasible LIKELY scenario")

        maximum = self.scenario_results[2]
        full_scope = self.scenario_results[3]
        if self.status is FeasibilityStatus.TIGHT_CAPACITY:
            if maximum.solver_status is not SolverRunStatus.INFEASIBLE:
                raise ValueError("TIGHT_CAPACITY requires MAX scenario infeasibility")
        elif self.status is FeasibilityStatus.FEASIBLE_WITH_TRADEOFFS:
            if maximum.solver_status not in {
                SolverRunStatus.OPTIMAL,
                SolverRunStatus.FEASIBLE,
            }:
                raise ValueError("tradeoff status requires MAX required scenario feasibility")
            if full_scope.solver_status is not SolverRunStatus.INFEASIBLE:
                raise ValueError("tradeoff status requires FULL_SCOPE_LIKELY infeasibility")
        elif self.status is FeasibilityStatus.FEASIBLE:
            for item in (maximum, full_scope):
                if item.solver_status not in {
                    SolverRunStatus.OPTIMAL,
                    SolverRunStatus.FEASIBLE,
                }:
                    raise ValueError("FEASIBLE requires MAX and FULL_SCOPE_LIKELY feasibility")
        return self


class FeasibilityRun(FeasibilityModel):
    """Self-contained Block 4 run artifacts consumed by recommendation assembly."""

    assessment: FeasibilityAssessment
    likely_solver_result: SolverResult
    baseline_workload_analysis: WorkloadAnalysis
