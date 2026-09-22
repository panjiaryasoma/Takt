from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field

from packages.contracts.enums import ReadinessStatus


class UserContext(BaseModel):
    age: int | None = Field(default=None, ge=0)
    student_status: bool | None = None
    country: str | None = None


class EligibilityRule(BaseModel):
    minimum_age: int | None = Field(default=None, ge=0)
    requires_student: bool = False
    allowed_regions: list[str] = Field(default_factory=list)


class ReadinessRequest(BaseModel):
    evaluated_at: datetime
    submission_deadline: datetime | None = None
    has_applicable_deadline_extension: bool = False
    eligibility: EligibilityRule = Field(default_factory=EligibilityRule)
    user: UserContext = Field(default_factory=UserContext)
    unresolved_critical_fields: list[str] = Field(default_factory=list)
    mandatory_information_complete: bool = True


class ReadinessResponse(BaseModel):
    status: ReadinessStatus
    blocking_reasons: list[str] = Field(default_factory=list)
    review_items: list[str] = Field(default_factory=list)
    passed_checks: list[str] = Field(default_factory=list)
    rule_version: str = "1.0"
