from datetime import UTC, datetime, timedelta

from engine.triage.service import evaluate_readiness
from packages.contracts.triage import EligibilityRule, ReadinessRequest, ReadinessStatus, UserContext

NOW = datetime(2026, 9, 21, 8, 0, tzinfo=UTC)
FUTURE = NOW + timedelta(days=10)


def test_unknown_student_status_is_review_not_blocked() -> None:
    result = evaluate_readiness(
        ReadinessRequest(
            evaluated_at=NOW,
            submission_deadline=FUTURE,
            eligibility=EligibilityRule(requires_student=True),
            user=UserContext(student_status=None),
        )
    )

    assert result.status == ReadinessStatus.NEEDS_REVIEW
    assert result.review_items == ["student_status_unknown"]


def test_explicit_false_student_status_is_blocked() -> None:
    result = evaluate_readiness(
        ReadinessRequest(
            evaluated_at=NOW,
            submission_deadline=FUTURE,
            eligibility=EligibilityRule(requires_student=True),
            user=UserContext(student_status=False),
        )
    )

    assert result.status == ReadinessStatus.ELIGIBILITY_BLOCKED
    assert result.blocking_reasons == ["student_status_requirement_not_met"]


def test_unknown_country_is_review_not_blocked() -> None:
    result = evaluate_readiness(
        ReadinessRequest(
            evaluated_at=NOW,
            submission_deadline=FUTURE,
            eligibility=EligibilityRule(allowed_regions=["Indonesia"]),
            user=UserContext(country=None),
        )
    )

    assert result.status == ReadinessStatus.NEEDS_REVIEW
    assert result.review_items == ["user_country_unknown"]
