"""Derived output models for Issue 3A Block 1 availability."""

from __future__ import annotations

from datetime import date
from typing import Annotated

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, StringConstraints

from packages.contracts import AvailabilityBlock

NonEmptyStr = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, strict=True),
]


class DerivedModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


class DailyCapacity(DerivedModel):
    local_date: date
    calendar_free_minutes: int = Field(ge=0)
    accepted_project_minutes: int = Field(ge=0)
    configured_project_limit_minutes: int = Field(ge=0)
    remaining_project_capacity_minutes: int = Field(ge=0)
    usable_project_minutes: int = Field(ge=0)


class AvailabilityResult(DerivedModel):
    timezone: NonEmptyStr
    horizon_start: AwareDatetime
    horizon_end: AwareDatetime
    busy_blocks: tuple[AvailabilityBlock, ...]
    available_blocks: tuple[AvailabilityBlock, ...]
    daily_capacity: tuple[DailyCapacity, ...]
