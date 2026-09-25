"""DTO Pydantic untuk kontrak data bersama Takt.

Model di sini mengikuti field yang diwajibkan oleh FEATURE_SCHEMA_FINAL.yaml.
Bentuk field yang belum didefinisikan secara rinci oleh source of truth tetap
dibuat longgar (`Any`) daripada ditebak diam-diam.
"""

from __future__ import annotations

from datetime import UTC
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator

from packages.contracts.enums import (
    AvailabilityType,
    FeasibilityStatus,
    ReadinessStatus,
)


class CompetitionBrief(BaseModel):
    """Canonical competition brief minimum sesuai kontrak aktif."""

    competition_id: str
    name: str
    organizer: str
    submission_deadline: AwareDatetime
    eligibility: Any
    deliverables: Any
    source_ids: list[str]
    unresolved_critical_fields: list[str]


class ReadinessTriage(BaseModel):
    """Satu-satunya kontrak canonical untuk output mesin triage."""

    status: ReadinessStatus
    blocking_reasons: list[str]
    review_items: list[str]
    passed_checks: list[str]
    rule_version: str


class Task(BaseModel):
    """Task workload dengan estimasi effort min/likely/max."""

    task_id: str
    name: str
    mandatory: bool
    dependencies: list[str]
    effort_min_hours: float = Field(ge=0)
    effort_likely_hours: float = Field(ge=0)
    effort_max_hours: float = Field(ge=0)


class AvailabilityBlock(BaseModel):
    """Timezone-aware availability interval with half-open [start, end) semantics."""

    model_config = ConfigDict(extra="forbid")

    start: AwareDatetime
    end: AwareDatetime
    timezone: str
    source: str
    availability_type: AvailabilityType

    @model_validator(mode="after")
    def validate_block(self) -> "AvailabilityBlock":
        if self.end.astimezone(UTC) <= self.start.astimezone(UTC):
            raise ValueError("availability end must be after start by instant")
        if self.start.second != 0 or self.start.microsecond != 0:
            raise ValueError("availability start must be minute-aligned")
        if self.end.second != 0 or self.end.microsecond != 0:
            raise ValueError("availability end must be minute-aligned")
        try:
            ZoneInfo(self.timezone)
        except ZoneInfoNotFoundError as exc:
            raise ValueError(f"unknown IANA timezone: {self.timezone}") from exc
        return self


class CandidateAllocation(BaseModel):
    """Candidate plan hasil solver sebelum menjadi commitment."""

    candidate_id: str
    work_blocks: list[Any]
    buffer_hours: float = Field(ge=0)
    hard_constraint_violations: list[str]
    assumptions: list[Any]

    @property
    def is_recommendable(self) -> bool:
        """Candidate hanya recommendable jika tidak punya hard violation."""

        return len(self.hard_constraint_violations) == 0


class Recommendation(BaseModel):
    """Recommendation advisory yang tetap membutuhkan keputusan manusia."""

    recommended_candidate_id: str
    recommended_next_work: Any
    suggested_windows: list[Any]
    alternatives: list[Any]
    rationale: list[Any]
    tradeoffs: list[Any]
    assumptions: list[Any]


class DecisionSupportReport(BaseModel):
    """Laporan decision-support agregat.

    `workload`, `capacity`, `risks`, dan `assumptions` belum punya schema rinci
    di kontrak aktif, jadi field tersebut diwajibkan hadir tetapi tidak
    dipersempit tipenya di Blok 1.
    """

    competition_brief: CompetitionBrief
    readiness: ReadinessTriage
    workload: Any
    capacity: Any
    feasibility: FeasibilityStatus
    recommendation: Recommendation | None
    risks: Any
    assumptions: Any
