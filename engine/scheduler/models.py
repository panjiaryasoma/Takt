"""Derived models for Issue 3A Block 3 CP-SAT scheduling."""

from __future__ import annotations

from enum import StrEnum
from typing import Annotated, Literal

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    StrictInt,
    StringConstraints,
    model_validator,
)

from packages.contracts.models import CandidateAllocation

NonEmptyStr = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, strict=True),
]


class SolverModel(BaseModel):
    """Strict/frozen model for solver configuration and derived output."""

    model_config = ConfigDict(extra="forbid", frozen=True, validate_default=True)


class SolverRunStatus(StrEnum):
    OPTIMAL = "OPTIMAL"
    FEASIBLE = "FEASIBLE"
    INFEASIBLE = "INFEASIBLE"
    UNKNOWN = "UNKNOWN"


class SolverConfig(SolverModel):
    """MVP solver policy frozen for Block 3.

    `effort_basis` is intentionally fixed to LIKELY. Min/max remain available
    in WorkloadAnalysis for later feasibility and risk interpretation.
    """

    submission_deadline: AwareDatetime
    buffer_target_minutes: StrictInt = Field(ge=0)
    effort_basis: Literal["LIKELY"] = "LIKELY"

    @model_validator(mode="after")
    def validate_deadline(self) -> SolverConfig:
        if self.submission_deadline.second != 0:
            raise ValueError("submission_deadline must be minute-aligned")
        if self.submission_deadline.microsecond != 0:
            raise ValueError("submission_deadline must be minute-aligned")
        return self


class SolverResult(SolverModel):
    status: SolverRunStatus
    candidate_allocations: tuple[CandidateAllocation, ...]
    reason_codes: tuple[NonEmptyStr, ...] = ()

    @model_validator(mode="after")
    def validate_status_shape(self) -> SolverResult:
        has_candidates = bool(self.candidate_allocations)
        if self.status in {SolverRunStatus.OPTIMAL, SolverRunStatus.FEASIBLE}:
            if not has_candidates:
                raise ValueError("feasible solver status requires at least one candidate")
        elif has_candidates:
            raise ValueError("infeasible/unknown solver status must not contain candidates")
        return self
