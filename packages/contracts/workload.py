"""Strict contracts for Issue 3A Block 2 workload analysis."""

from __future__ import annotations

from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, StrictInt, StringConstraints, model_validator

from packages.contracts.models import Task

NonEmptyStr = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, strict=True),
]


class WorkloadContract(BaseModel):
    """Strict and frozen boundary model for workload inputs and outputs."""

    model_config = ConfigDict(extra="forbid", frozen=True, validate_default=True)


class EffortRange(WorkloadContract):
    """Integer-minute effort range without derived fake precision."""

    min_minutes: StrictInt = Field(ge=0)
    likely_minutes: StrictInt = Field(ge=0)
    max_minutes: StrictInt = Field(ge=0)

    @model_validator(mode="after")
    def validate_order(self) -> "EffortRange":
        if not self.min_minutes <= self.likely_minutes <= self.max_minutes:
            raise ValueError("effort range must satisfy min <= likely <= max")
        return self


class WorkloadAssumption(WorkloadContract):
    """Traceable assumption, either task-specific or global."""

    task_id: NonEmptyStr | None = None
    description: NonEmptyStr


class WorkloadInput(WorkloadContract):
    """Canonical Block 2 input before graph and effort analysis."""

    tasks: tuple[Task, ...]
    assumptions: tuple[WorkloadAssumption, ...] = ()


class WorkloadAnalysis(WorkloadContract):
    """Deterministic workload analysis consumed later by the solver layer."""

    tasks: tuple[Task, ...]
    topological_order: tuple[NonEmptyStr, ...]
    required_task_ids: tuple[NonEmptyStr, ...]
    declared_mandatory_effort: EffortRange
    required_effort: EffortRange
    optional_effort: EffortRange
    assumptions: tuple[WorkloadAssumption, ...]
