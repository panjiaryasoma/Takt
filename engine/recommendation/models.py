"""Strict internal models for Issue 3A Block 5 recommendation assembly."""

from __future__ import annotations

from datetime import UTC
from typing import Annotated

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    StrictInt,
    StringConstraints,
    model_validator,
)

from engine.feasibility.models import FeasibilityRun
from packages.contracts.enums import FeasibilityStatus, RecommendationAction
from packages.contracts.source import CanonicalCompetitionReport
from packages.contracts.workload import WorkloadAssumption

NonEmptyStr = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, strict=True),
]
PositiveStrictInt = Annotated[StrictInt, Field(gt=0)]
NonNegativeStrictInt = Annotated[StrictInt, Field(ge=0)]
PositiveVersion = Annotated[StrictInt, Field(ge=1)]


class RecommendationModel(BaseModel):
    """Strict/frozen internal Block 5 model."""

    model_config = ConfigDict(extra="forbid", frozen=True, validate_default=True)


class RecommendationTraceContext(RecommendationModel):
    competition_id: NonEmptyStr
    report_version: PositiveVersion

    @classmethod
    def from_canonical_report(
        cls,
        report: CanonicalCompetitionReport,
    ) -> RecommendationTraceContext:
        """Copy trace identifiers from the canonical report source of truth."""

        if not isinstance(report, CanonicalCompetitionReport):
            raise TypeError("report must be CanonicalCompetitionReport")
        validated = CanonicalCompetitionReport.model_validate(
            report.model_dump(mode="python")
        )
        return cls(
            competition_id=validated.competition_id,
            report_version=validated.report_version,
        )


class RecommendedNextWork(RecommendationModel):
    task_id: NonEmptyStr
    task_name: NonEmptyStr
    start: AwareDatetime
    end: AwareDatetime
    allocated_minutes: PositiveStrictInt
    availability_source: NonEmptyStr

    @model_validator(mode="after")
    def validate_interval(self) -> RecommendedNextWork:
        _validate_exact_minutes(self.start, self.end, self.allocated_minutes)
        return self


class SuggestedWorkWindow(RecommendationModel):
    task_id: NonEmptyStr
    start: AwareDatetime
    end: AwareDatetime
    allocated_minutes: PositiveStrictInt
    availability_source: NonEmptyStr

    @model_validator(mode="after")
    def validate_interval(self) -> SuggestedWorkWindow:
        _validate_exact_minutes(self.start, self.end, self.allocated_minutes)
        return self


class RecommendationAlternative(RecommendationModel):
    candidate_id: NonEmptyStr
    buffer_minutes: NonNegativeStrictInt
    recommended_next_work: RecommendedNextWork | None
    suggested_windows: tuple[SuggestedWorkWindow, ...]

    @model_validator(mode="after")
    def validate_alternative(self) -> RecommendationAlternative:
        _validate_window_projection(
            self.suggested_windows,
            self.recommended_next_work,
            owner="alternative",
        )
        return self


class RecommendationPayload(RecommendationModel):
    recommended_candidate_id: NonEmptyStr
    recommended_next_work: RecommendedNextWork | None
    suggested_windows: tuple[SuggestedWorkWindow, ...]
    alternatives: tuple[RecommendationAlternative, ...] = ()
    rationale: tuple[NonEmptyStr, ...]
    tradeoffs: tuple[NonEmptyStr, ...]
    assumptions: tuple[WorkloadAssumption, ...]

    @model_validator(mode="after")
    def validate_payload(self) -> RecommendationPayload:
        if not self.rationale:
            raise ValueError("recommendation payload requires non-empty rationale")

        alternative_ids = tuple(item.candidate_id for item in self.alternatives)
        if len(set(alternative_ids)) != len(alternative_ids):
            raise ValueError("recommendation alternatives must use unique candidate IDs")
        if self.recommended_candidate_id in alternative_ids:
            raise ValueError("primary candidate must not appear in recommendation alternatives")

        _validate_window_projection(
            self.suggested_windows,
            self.recommended_next_work,
            owner="recommendation",
        )
        return self


class RecommendationAssembly(RecommendationModel):
    recommendation_payload: RecommendationPayload | None
    primary_candidate_id: NonEmptyStr | None
    alternative_candidate_ids: tuple[NonEmptyStr, ...] = ()
    allowed_actions: tuple[RecommendationAction, ...]
    source_feasibility_status: FeasibilityStatus
    source_competition_id: NonEmptyStr
    source_report_version: PositiveVersion

    @model_validator(mode="after")
    def validate_assembly(self) -> RecommendationAssembly:
        if len(set(self.alternative_candidate_ids)) != len(self.alternative_candidate_ids):
            raise ValueError("alternative_candidate_ids must be unique")
        if len(set(self.allowed_actions)) != len(self.allowed_actions):
            raise ValueError("allowed_actions must not contain duplicate values")
        if (
            self.primary_candidate_id is not None
            and self.primary_candidate_id in self.alternative_candidate_ids
        ):
            raise ValueError("primary candidate must not appear in alternative_candidate_ids")

        no_recommendation_actions = (
            RecommendationAction.EDIT_CONSTRAINTS,
            RecommendationAction.IGNORE,
        )
        recommendation_actions = (
            RecommendationAction.ACCEPT,
            RecommendationAction.EDIT_CONSTRAINTS,
            RecommendationAction.IGNORE,
        )
        recommendation_actions_with_alternatives = (
            RecommendationAction.ACCEPT,
            RecommendationAction.CHOOSE_ALTERNATIVE,
            RecommendationAction.EDIT_CONSTRAINTS,
            RecommendationAction.IGNORE,
        )

        not_feasible = (
            self.source_feasibility_status
            is FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS
        )
        if not_feasible:
            if self.recommendation_payload is not None:
                raise ValueError("not-feasible assembly must not contain recommendation payload")
            if self.primary_candidate_id is not None:
                raise ValueError("not-feasible assembly must not expose a primary candidate")
            if self.alternative_candidate_ids:
                raise ValueError("not-feasible assembly must not expose alternatives")
            if self.allowed_actions != no_recommendation_actions:
                raise ValueError(
                    "not-feasible assembly actions must be EDIT_CONSTRAINTS then IGNORE"
                )
            return self

        if self.recommendation_payload is None:
            raise ValueError("recommendable feasibility status requires recommendation payload")
        if self.primary_candidate_id is None:
            raise ValueError("recommendable feasibility status requires a primary candidate")
        if self.recommendation_payload.recommended_candidate_id != self.primary_candidate_id:
            raise ValueError("payload candidate must match assembly primary candidate")

        payload_alternative_ids = tuple(
            item.candidate_id for item in self.recommendation_payload.alternatives
        )
        if payload_alternative_ids != self.alternative_candidate_ids:
            raise ValueError("payload alternatives must match assembly alternative_candidate_ids")

        expected_actions = (
            recommendation_actions_with_alternatives
            if self.alternative_candidate_ids
            else recommendation_actions
        )
        if self.allowed_actions != expected_actions:
            raise ValueError(
                "recommendable assembly actions must match alternative availability"
            )
        if (
            self.source_feasibility_status
            is FeasibilityStatus.FEASIBLE_WITH_TRADEOFFS
            and not self.recommendation_payload.tradeoffs
        ):
            raise ValueError("tradeoff feasibility status requires non-empty tradeoffs")
        return self


class RecommendationBuildInput(RecommendationModel):
    feasibility_run: FeasibilityRun
    trace_context: RecommendationTraceContext


def _validate_window_projection(
    windows: tuple[SuggestedWorkWindow, ...],
    next_work: RecommendedNextWork | None,
    *,
    owner: str,
) -> None:
    ordered = tuple(
        sorted(
            windows,
            key=lambda item: (
                item.start.astimezone(UTC),
                item.task_id,
                item.end.astimezone(UTC),
            ),
        )
    )
    if windows != ordered:
        raise ValueError(f"{owner} suggested_windows must use canonical chronological order")

    if not windows:
        if next_work is not None:
            raise ValueError(
                f"{owner} recommended_next_work must be None when suggested_windows is empty"
            )
        return

    if next_work is None:
        raise ValueError(
            f"{owner} recommended_next_work is required when suggested_windows is non-empty"
        )
    first = windows[0]
    if (
        next_work.task_id != first.task_id
        or next_work.start != first.start
        or next_work.end != first.end
        or next_work.allocated_minutes != first.allocated_minutes
        or next_work.availability_source != first.availability_source
    ):
        raise ValueError(
            f"{owner} recommended_next_work must project the first suggested work window"
        )


def _validate_exact_minutes(start, end, allocated_minutes: int) -> None:
    if start.second != 0 or start.microsecond != 0:
        raise ValueError("recommendation work interval start must be minute-aligned")
    if end.second != 0 or end.microsecond != 0:
        raise ValueError("recommendation work interval end must be minute-aligned")

    start_utc = start.astimezone(UTC)
    end_utc = end.astimezone(UTC)
    if end_utc <= start_utc:
        raise ValueError("recommendation work interval end must be after start")
    elapsed_seconds = (end_utc - start_utc).total_seconds()
    if elapsed_seconds != allocated_minutes * 60:
        raise ValueError("allocated_minutes must equal exact recommendation interval duration")
