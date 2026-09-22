from datetime import UTC, datetime, timedelta

import pytest

from engine.triage.scope import ResolvedEligibilityScope
from engine.triage.service import evaluate_readiness
from packages.contracts import ReadinessStatus, ReadinessTriage
from packages.contracts.triage import EligibilityRule, ReadinessRequest, UserContext


NOW = datetime(2026, 9, 21, 8, 0, tzinfo=UTC)
FUTURE = NOW + timedelta(days=10)
PAST = NOW - timedelta(days=1)


@pytest.mark.parametrize(
    (
        "case_input",
        "expected_status",
        "expected_blocking",
        "expected_review",
        "expected_passed",
    ),
    [
        pytest.param(
            ReadinessRequest(
                evaluated_at=NOW,
                submission_deadline=FUTURE,
                eligibility=EligibilityRule(
                    minimum_age=18,
                    requires_student=True,
                ),
                user=UserContext(age=21, student_status=True),
            ),
            ReadinessStatus.READY_TO_EVALUATE,
            [],
            [],
            [
                "deadline_valid",
                "minimum_age_met",
                "student_status_met",
                "mandatory_information_complete",
            ],
            id="TRIAGE-001-ready-baseline",
        ),
        pytest.param(
            ReadinessRequest(
                evaluated_at=NOW,
                submission_deadline=PAST,
                user=UserContext(age=21),
            ),
            ReadinessStatus.DEADLINE_PASSED,
            ["authoritative_submission_deadline_passed"],
            [],
            [],
            id="TRIAGE-002-deadline-passed",
        ),
        pytest.param(
            ReadinessRequest(
                evaluated_at=NOW,
                submission_deadline=FUTURE,
                eligibility=EligibilityRule(requires_student=True),
                user=UserContext(student_status=False),
            ),
            ReadinessStatus.ELIGIBILITY_BLOCKED,
            ["student_status_requirement_not_met"],
            [],
            ["deadline_valid"],
            id="TRIAGE-003-eligibility-blocked",
        ),
        pytest.param(
            ReadinessRequest(
                evaluated_at=NOW,
                submission_deadline=FUTURE,
                eligibility=EligibilityRule(minimum_age=18),
                user=UserContext(age=None),
            ),
            ReadinessStatus.NEEDS_REVIEW,
            [],
            ["user_age_unknown"],
            ["deadline_valid"],
            id="TRIAGE-004-unknown-user-attribute",
        ),
        pytest.param(
            ReadinessRequest(
                evaluated_at=NOW,
                submission_deadline=FUTURE,
                unresolved_critical_fields=["submission_deadline"],
            ),
            ReadinessStatus.NEEDS_REVIEW,
            [],
            ["unresolved_critical_field:submission_deadline"],
            [],
            id="TRIAGE-005-critical-deadline-conflict",
        ),
        pytest.param(
            ReadinessRequest(
                evaluated_at=NOW,
                submission_deadline=FUTURE,
                mandatory_information_complete=False,
            ),
            ReadinessStatus.INSUFFICIENT_INFORMATION,
            [],
            ["mandatory_competition_information_missing"],
            ["deadline_valid"],
            id="TRIAGE-006-mandatory-information-missing",
        ),
        pytest.param(
            ReadinessRequest(
                evaluated_at=NOW,
                submission_deadline=PAST,
                has_applicable_deadline_extension=True,
                eligibility=EligibilityRule(minimum_age=18),
                user=UserContext(age=21),
            ),
            ReadinessStatus.READY_TO_EVALUATE,
            [],
            [],
            [
                "deadline_valid",
                "minimum_age_met",
                "mandatory_information_complete",
            ],
            id="TRIAGE-007-authoritative-deadline-extension",
        ),
    ],
)
def test_triage_001_through_007_acceptance(
    case_input: ReadinessRequest,
    expected_status: ReadinessStatus,
    expected_blocking: list[str],
    expected_review: list[str],
    expected_passed: list[str],
) -> None:
    result = evaluate_readiness(case_input)

    assert type(result) is ReadinessTriage
    assert result.status is expected_status
    assert result.blocking_reasons == expected_blocking
    assert result.review_items == expected_review
    assert result.passed_checks == expected_passed
    assert result.rule_version == "1.0"


def test_triage_008_scoped_category_rule() -> None:
    resolved_scope = ResolvedEligibilityScope(
        selected_scope="student_category",
        effective_rule=EligibilityRule(
            minimum_age=18,
            requires_student=True,
            allowed_regions=["global"],
        ),
        provenance=(
            "general_event_scope:broad",
            "selected_category:student",
            "category_rule:current_enrollment_required",
        ),
    )

    assert resolved_scope.selected_scope == "student_category"
    assert resolved_scope.effective_rule.requires_student is True
    assert "selected_category:student" in resolved_scope.provenance
    assert "category_rule:current_enrollment_required" in resolved_scope.provenance

    case_input = ReadinessRequest(
        evaluated_at=NOW,
        submission_deadline=FUTURE,
        eligibility=resolved_scope.effective_rule,
        user=UserContext(
            age=21,
            student_status=True,
            country="Indonesia",
        ),
    )

    result = evaluate_readiness(case_input)

    assert type(result) is ReadinessTriage
    assert result.status is ReadinessStatus.READY_TO_EVALUATE
    assert result.blocking_reasons == []
    assert result.review_items == []
    assert result.passed_checks == [
        "deadline_valid",
        "minimum_age_met",
        "student_status_met",
        "mandatory_information_complete",
    ]
    assert result.rule_version == "1.0"


def test_resolved_scope_requires_traceable_provenance() -> None:
    with pytest.raises(
        ValueError,
        match="resolved eligibility scope requires provenance",
    ):
        ResolvedEligibilityScope(
            selected_scope="student_category",
            effective_rule=EligibilityRule(requires_student=True),
            provenance=(),
        )


def test_same_input_produces_identical_output() -> None:
    case_input = ReadinessRequest(
        evaluated_at=NOW,
        submission_deadline=FUTURE,
        eligibility=EligibilityRule(
            minimum_age=18,
            requires_student=True,
            allowed_regions=["Indonesia"],
        ),
        user=UserContext(
            age=21,
            student_status=True,
            country="Indonesia",
        ),
    )

    first = evaluate_readiness(case_input).model_dump(mode="json")
    second = evaluate_readiness(case_input).model_dump(mode="json")

    assert first == second


@pytest.mark.parametrize(
    "case_input",
    [
        pytest.param(
            ReadinessRequest(
                evaluated_at=NOW,
                submission_deadline=FUTURE,
                eligibility=EligibilityRule(minimum_age=18),
                user=UserContext(age=None),
            ),
            id="unknown-age",
        ),
        pytest.param(
            ReadinessRequest(
                evaluated_at=NOW,
                submission_deadline=FUTURE,
                eligibility=EligibilityRule(requires_student=True),
                user=UserContext(student_status=None),
            ),
            id="unknown-student-status",
        ),
        pytest.param(
            ReadinessRequest(
                evaluated_at=NOW,
                submission_deadline=FUTURE,
                eligibility=EligibilityRule(allowed_regions=["Indonesia"]),
                user=UserContext(country=None),
            ),
            id="unknown-country",
        ),
    ],
)
def test_unknown_user_attribute_is_review_not_failure(
    case_input: ReadinessRequest,
) -> None:
    result = evaluate_readiness(case_input)

    assert result.status is ReadinessStatus.NEEDS_REVIEW
    assert result.blocking_reasons == []


def test_explicit_failed_attribute_is_eligibility_blocked() -> None:
    case_input = ReadinessRequest(
        evaluated_at=NOW,
        submission_deadline=FUTURE,
        eligibility=EligibilityRule(requires_student=True),
        user=UserContext(student_status=False),
    )

    result = evaluate_readiness(case_input)

    assert result.status is ReadinessStatus.ELIGIBILITY_BLOCKED
    assert result.blocking_reasons == [
        "student_status_requirement_not_met",
    ]


def test_triage_output_contains_no_recommendation_or_participation_directive() -> None:
    case_input = ReadinessRequest(
        evaluated_at=NOW,
        submission_deadline=FUTURE,
    )

    payload = evaluate_readiness(case_input).model_dump(mode="json")

    assert set(payload) == {
        "status",
        "blocking_reasons",
        "review_items",
        "passed_checks",
        "rule_version",
    }

    serialized = str(payload).lower()
    assert "join" not in serialized
    assert "do_not_join" not in serialized
    assert "recommendation" not in serialized
