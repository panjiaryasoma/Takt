from datetime import UTC, datetime

import pytest
from pydantic import ValidationError

from packages.contracts import (
    AllocationBlock,
    AvailabilityBlock,
    AvailabilityType,
    CandidateAllocation,
    CanonicalFieldState,
    CommitmentType,
    CompetitionBrief,
    DecisionSupportReport,
    FeasibilityStatus,
    ReadinessStatus,
    ReadinessTriage,
    Recommendation,
    RecommendationAction,
    Task,
)

NOW = datetime(2026, 9, 22, 8, 0, tzinfo=UTC)
LATER = datetime(2026, 9, 22, 10, 0, tzinfo=UTC)


EXPECTED_ENUM_WIRE_VALUES = {
    ReadinessStatus: [
        "READY_TO_EVALUATE",
        "NEEDS_REVIEW",
        "ELIGIBILITY_BLOCKED",
        "DEADLINE_PASSED",
        "INSUFFICIENT_INFORMATION",
    ],
    FeasibilityStatus: [
        "FEASIBLE",
        "FEASIBLE_WITH_TRADEOFFS",
        "TIGHT_CAPACITY",
        "NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS",
    ],
    CanonicalFieldState: [
        "VERIFIED",
        "SINGLE_SOURCE",
        "CONFLICT",
        "MISSING",
        "UNVERIFIED",
    ],
    CommitmentType: [
        "FIXED",
        "FLEXIBLE",
    ],
    RecommendationAction: [
        "ACCEPT",
        "CHOOSE_ALTERNATIVE",
        "EDIT_CONSTRAINTS",
        "IGNORE",
    ],
    AvailabilityType: [
        "AVAILABLE",
        "FIXED_BUSY",
        "FLEXIBLE_BUSY",
        "ACCEPTED_PROJECT_COMMITMENT",
    ],
}


@pytest.mark.parametrize(
    ("enum_class", "expected_values"),
    EXPECTED_ENUM_WIRE_VALUES.items(),
)
def test_all_enum_wire_values_are_frozen(enum_class, expected_values) -> None:
    assert [member.value for member in enum_class] == expected_values


def test_required_field_missing_is_rejected() -> None:
    with pytest.raises(ValidationError):
        CompetitionBrief(
            competition_id="cmp_001",
            name="Example",
            organizer="Org",
            submission_deadline=LATER,
            eligibility={},
            deliverables=[],
            source_ids=["src_1"],
            # unresolved_critical_fields sengaja hilang
        )


def test_invalid_readiness_enum_is_rejected() -> None:
    with pytest.raises(ValidationError):
        ReadinessTriage(
            status="READY",
            blocking_reasons=[],
            review_items=[],
            passed_checks=[],
            rule_version="1.0",
        )


def test_invalid_availability_type_is_rejected() -> None:
    with pytest.raises(ValidationError):
        AvailabilityBlock(
            start=NOW,
            end=LATER,
            timezone="Asia/Jakarta",
            source="MANUAL",
            availability_type="BUSY",
        )


def test_readiness_serialization_matches_wire_contract() -> None:
    triage = ReadinessTriage(
        status=ReadinessStatus.READY_TO_EVALUATE,
        blocking_reasons=[],
        review_items=[],
        passed_checks=["deadline_valid"],
        rule_version="1.0",
    )

    payload = triage.model_dump(mode="json")
    assert payload["status"] == "READY_TO_EVALUATE"


def test_availability_serialization_matches_wire_contract() -> None:
    block = AvailabilityBlock(
        start=NOW,
        end=LATER,
        timezone="Asia/Jakarta",
        source="MANUAL",
        availability_type=AvailabilityType.FIXED_BUSY,
    )

    payload = block.model_dump(mode="json")
    assert payload["availability_type"] == "FIXED_BUSY"


def test_task_requires_three_effort_estimates() -> None:
    with pytest.raises(ValidationError):
        Task(
            task_id="task_1",
            name="Build demo",
            mandatory=True,
            dependencies=[],
            assumptions=[],
            effort_likely_minutes=120,
            effort_max_minutes=180,
            # effort_min_minutes sengaja hilang
        )


def test_candidate_with_hard_violation_is_not_recommendable() -> None:
    candidate = CandidateAllocation(
        candidate_id="ca_1",
        work_blocks=(),
        buffer_minutes=120,
        hard_constraint_violations=("deadline_overlap",),
        assumptions=(),
    )
    assert candidate.is_recommendable is False


def test_allocation_block_serializes_integer_minutes() -> None:
    block = AllocationBlock(
        task_id="task_1",
        start=NOW,
        end=LATER,
        allocated_minutes=120,
        availability_source="derived:work_window:0",
    )
    assert block.model_dump(mode="json")["allocated_minutes"] == 120


def test_decision_support_report_accepts_null_recommendation() -> None:
    brief = CompetitionBrief(
        competition_id="cmp_001",
        name="Example",
        organizer="Org",
        submission_deadline=LATER,
        eligibility={},
        deliverables=[],
        source_ids=["src_1"],
        unresolved_critical_fields=[],
    )
    readiness = ReadinessTriage(
        status=ReadinessStatus.INSUFFICIENT_INFORMATION,
        blocking_reasons=[],
        review_items=["missing_details"],
        passed_checks=[],
        rule_version="1.0",
    )

    report = DecisionSupportReport(
        competition_brief=brief,
        readiness=readiness,
        workload={},
        capacity={},
        feasibility=FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS,
        recommendation=None,
        risks=[],
        assumptions=[],
    )

    assert report.recommendation is None


def test_recommendation_required_fields_are_enforced() -> None:
    with pytest.raises(ValidationError):
        Recommendation(
            recommended_candidate_id="ca_1",
            recommended_next_work={},
            suggested_windows=[],
            alternatives=[],
            rationale=[],
            tradeoffs=[],
            # assumptions sengaja hilang
        )


def test_competition_brief_rejects_naive_submission_deadline() -> None:
    with pytest.raises(ValidationError):
        CompetitionBrief(
            competition_id="cmp_001",
            name="Example",
            organizer="Org",
            submission_deadline="2026-09-22T10:00:00",
            eligibility={},
            deliverables=[],
            source_ids=["src_1"],
            unresolved_critical_fields=[],
        )
