from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
from pydantic import ValidationError

from engine.recommendation.models import (
    RecommendationAssembly,
    RecommendationPayload,
    RecommendationTraceContext,
    RecommendedNextWork,
    SuggestedWorkWindow,
)
from packages.contracts.enums import (
    CanonicalFieldState,
    FeasibilityStatus,
    RecommendationAction,
)
from packages.contracts.source import (
    CORE_CANONICAL_FIELDS,
    CanonicalCompetitionReport,
    CanonicalField,
)

START = datetime(2026, 10, 1, 9, 0, tzinfo=UTC)


def _canonical_report() -> CanonicalCompetitionReport:
    return CanonicalCompetitionReport(
        competition_id="cmp-001",
        report_version=7,
        source_ids=["src-001"],
        canonical_fields={
            field_name: CanonicalField(
                field_name=field_name,
                state=CanonicalFieldState.MISSING,
            )
            for field_name in CORE_CANONICAL_FIELDS
        },
        unresolved_critical_fields=[],
    )


# REC-037
def test_trace_context_factory_preserves_real_canonical_identifiers() -> None:
    context = RecommendationTraceContext.from_canonical_report(_canonical_report())
    assert context.competition_id == "cmp-001"
    assert context.report_version == 7


# REC-038
def test_trace_context_rejects_invalid_report_version() -> None:
    with pytest.raises(ValidationError):
        RecommendationTraceContext(
            competition_id="cmp-001",
            report_version=0,
        )


# REC-031
def test_internal_payload_is_frozen_and_tuple_based() -> None:
    payload = RecommendationPayload(
        recommended_candidate_id="candidate-001",
        recommended_next_work=None,
        suggested_windows=(),
        alternatives=(),
        rationale=("A rationale.",),
        tradeoffs=(),
        assumptions=(),
    )
    assert isinstance(payload.rationale, tuple)
    with pytest.raises(ValidationError):
        payload.rationale = ("mutated",)


def test_suggested_window_rejects_mismatched_duration() -> None:
    with pytest.raises(ValidationError, match="allocated_minutes"):
        SuggestedWorkWindow(
            task_id="core",
            start=START,
            end=START + timedelta(minutes=60),
            allocated_minutes=30,
            availability_source="window-1",
        )



def _window(
    *,
    task_id: str = "core",
    start: datetime = START,
    minutes: int = 60,
) -> SuggestedWorkWindow:
    return SuggestedWorkWindow(
        task_id=task_id,
        start=start,
        end=start + timedelta(minutes=minutes),
        allocated_minutes=minutes,
        availability_source="window-1",
    )


def _next_work(window: SuggestedWorkWindow, *, task_id: str | None = None) -> RecommendedNextWork:
    return RecommendedNextWork(
        task_id=task_id or window.task_id,
        task_name="Core deliverable",
        start=window.start,
        end=window.end,
        allocated_minutes=window.allocated_minutes,
        availability_source=window.availability_source,
    )


def _payload(
    *,
    windows: tuple[SuggestedWorkWindow, ...] = (),
    next_work: RecommendedNextWork | None = None,
    alternatives: tuple[str, ...] = (),
    rationale: tuple[str, ...] = ("A rationale.",),
    tradeoffs: tuple[str, ...] = (),
) -> RecommendationPayload:
    return RecommendationPayload(
        recommended_candidate_id="candidate-001",
        recommended_next_work=next_work,
        suggested_windows=windows,
        alternatives=alternatives,
        rationale=rationale,
        tradeoffs=tradeoffs,
        assumptions=(),
    )


def test_payload_rejects_non_empty_mvp_alternatives() -> None:
    with pytest.raises(ValidationError, match="does not support alternatives"):
        _payload(alternatives=("candidate-002",))


def test_payload_requires_non_empty_rationale() -> None:
    with pytest.raises(ValidationError, match="non-empty rationale"):
        _payload(rationale=())


def test_payload_rejects_windows_without_next_work() -> None:
    window = _window()
    with pytest.raises(ValidationError, match="recommended_next_work is required"):
        _payload(windows=(window,), next_work=None)


def test_payload_rejects_next_work_without_windows() -> None:
    window = _window()
    with pytest.raises(ValidationError, match="must be None"):
        _payload(next_work=_next_work(window))


def test_payload_requires_next_work_to_match_first_window_projection() -> None:
    first = _window(task_id="core", start=START)
    second = _window(task_id="optional", start=START + timedelta(hours=2))
    with pytest.raises(ValidationError, match="first suggested work window"):
        _payload(
            windows=(first, second),
            next_work=_next_work(second),
        )


@pytest.mark.parametrize("model_name", ("window", "next"))
def test_recommendation_intervals_require_minute_alignment(model_name: str) -> None:
    start = START
    end = START + timedelta(minutes=60, seconds=59)
    kwargs = {
        "task_id": "core",
        "start": start,
        "end": end,
        "allocated_minutes": 60,
        "availability_source": "window-1",
    }
    if model_name == "next":
        kwargs["task_name"] = "Core deliverable"
        constructor = RecommendedNextWork
    else:
        constructor = SuggestedWorkWindow

    with pytest.raises(ValidationError, match="minute-aligned"):
        constructor(**kwargs)


def test_recommendation_interval_requires_exact_duration() -> None:
    with pytest.raises(ValidationError, match="exact recommendation interval duration"):
        SuggestedWorkWindow(
            task_id="core",
            start=START,
            end=START + timedelta(minutes=61),
            allocated_minutes=60,
            availability_source="window-1",
        )


def test_not_feasible_assembly_rejects_accept_action() -> None:
    with pytest.raises(ValidationError, match="not-feasible assembly actions"):
        RecommendationAssembly(
            recommendation_payload=None,
            primary_candidate_id=None,
            alternative_candidate_ids=(),
            allowed_actions=(RecommendationAction.ACCEPT,),
            source_feasibility_status=(
                FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS
            ),
            source_competition_id="cmp-001",
            source_report_version=1,
        )


def test_recommendable_status_requires_payload_and_primary() -> None:
    with pytest.raises(ValidationError, match="requires recommendation payload"):
        RecommendationAssembly(
            recommendation_payload=None,
            primary_candidate_id=None,
            alternative_candidate_ids=(),
            allowed_actions=(
                RecommendationAction.ACCEPT,
                RecommendationAction.EDIT_CONSTRAINTS,
                RecommendationAction.IGNORE,
            ),
            source_feasibility_status=FeasibilityStatus.FEASIBLE,
            source_competition_id="cmp-001",
            source_report_version=1,
        )


def test_assembly_rejects_duplicate_allowed_actions() -> None:
    payload = _payload()
    with pytest.raises(ValidationError, match="duplicate"):
        RecommendationAssembly(
            recommendation_payload=payload,
            primary_candidate_id="candidate-001",
            alternative_candidate_ids=(),
            allowed_actions=(
                RecommendationAction.ACCEPT,
                RecommendationAction.ACCEPT,
                RecommendationAction.EDIT_CONSTRAINTS,
                RecommendationAction.IGNORE,
            ),
            source_feasibility_status=FeasibilityStatus.FEASIBLE,
            source_competition_id="cmp-001",
            source_report_version=1,
        )


def test_assembly_rejects_payload_and_assembly_alternative_mismatch() -> None:
    payload = _payload()

    with pytest.raises(ValidationError, match="must match"):
        RecommendationAssembly(
            recommendation_payload=payload,
            primary_candidate_id="candidate-001",
            alternative_candidate_ids=("candidate-002",),
            allowed_actions=(
                RecommendationAction.ACCEPT,
                RecommendationAction.EDIT_CONSTRAINTS,
                RecommendationAction.IGNORE,
            ),
            source_feasibility_status=FeasibilityStatus.FEASIBLE,
            source_competition_id="cmp-001",
            source_report_version=1,
        )


def test_assembly_rejects_non_empty_mvp_alternatives() -> None:
    payload = _payload().model_copy(
        update={"alternatives": ("candidate-002",)}
    )
    with pytest.raises(ValidationError, match="does not support alternative"):
        RecommendationAssembly(
            recommendation_payload=payload,
            primary_candidate_id="candidate-001",
            alternative_candidate_ids=("candidate-002",),
            allowed_actions=(
                RecommendationAction.ACCEPT,
                RecommendationAction.CHOOSE_ALTERNATIVE,
                RecommendationAction.EDIT_CONSTRAINTS,
                RecommendationAction.IGNORE,
            ),
            source_feasibility_status=FeasibilityStatus.FEASIBLE,
            source_competition_id="cmp-001",
            source_report_version=1,
        )


def test_tradeoff_status_requires_non_empty_tradeoff_explanation() -> None:
    payload = _payload()
    with pytest.raises(ValidationError, match="requires non-empty tradeoffs"):
        RecommendationAssembly(
            recommendation_payload=payload,
            primary_candidate_id="candidate-001",
            alternative_candidate_ids=(),
            allowed_actions=(
                RecommendationAction.ACCEPT,
                RecommendationAction.EDIT_CONSTRAINTS,
                RecommendationAction.IGNORE,
            ),
            source_feasibility_status=FeasibilityStatus.FEASIBLE_WITH_TRADEOFFS,
            source_competition_id="cmp-001",
            source_report_version=1,
        )
