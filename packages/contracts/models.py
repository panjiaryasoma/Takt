"""DTO Pydantic untuk kontrak data bersama Takt.

Model di sini mengikuti field yang diwajibkan oleh FEATURE_SCHEMA_FINAL.yaml.
Bentuk field yang belum didefinisikan secara rinci oleh source of truth tetap
dibuat longgar (`Any`) daripada ditebak diam-diam.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field

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
    submission_deadline: datetime
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
    """Blok availability minimum yang dikirim ke planning/solver layer."""

    start: datetime
    end: datetime
    timezone: str
    source: str
    availability_type: AvailabilityType


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
