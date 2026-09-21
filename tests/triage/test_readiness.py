from datetime import datetime, timedelta, timezone

import pytest

from engine.triage.service import evaluate_readiness
from packages.contracts.triage import (
    EligibilityRule,
    ReadinessRequest,
    ReadinessStatus,
    UserContext,
)

NOW = datetime(2026, 9, 21, 8, 0, tzinfo=timezone.utc)
FUTURE = NOW + timedelta(days=10)
PAST = NOW - timedelta(days=1)


@pytest.mark.parametrize(
    ("request", "expected"),
    [
        (
            ReadinessRequest(
                evaluated_at=NOW,
                submission_deadline=FUTURE,
                eligibility=EligibilityRule(minimum_age=18, requires_student=True),
                user=UserContext(age=21, student_status=True),
            ),
            ReadinessStatus.READY_TO_EVALUATE,
        ),
        (
            ReadinessRequest(
                evaluated_at=NOW,
                submission_deadline=PAST,
                user=UserContext(age=21),
            ),
            ReadinessStatus.DEADLINE_PASSED,
        ),
        (
            ReadinessRequest(
                evaluated_at=NOW,
                submission_deadline=FUTURE,
                eligibility=EligibilityRule(requires_student=True),
                user=UserContext(student_status=False),
            ),
            ReadinessStatus.ELIGIBILITY_BLOCKED,
        ),
        (
            ReadinessRequest(
                evaluated_at=NOW,
                submission_deadline=FUTURE,
                eligibility=EligibilityRule(minimum_age=18),
                user=UserContext(age=None),
            ),
            ReadinessStatus.NEEDS_REVIEW,
        ),
        (
            ReadinessRequest(
                evaluated_at=NOW,
                submission_deadline=FUTURE,
                unresolved_critical_fields=["submission_deadline"],
            ),
            ReadinessStatus.NEEDS_REVIEW,
        ),
        (
            ReadinessRequest(
                evaluated_at=NOW,
                submission_deadline=FUTURE,
                mandatory_information_complete=False,
            ),
            ReadinessStatus.INSUFFICIENT_INFORMATION,
        ),
        (
            ReadinessRequest(
                evaluated_at=NOW,
                submission_deadline=PAST,
                has_applicable_deadline_extension=True,
                eligibility=EligibilityRule(minimum_age=18),
                user=UserContext(age=21),
            ),
            ReadinessStatus.READY_TO_EVALUATE,
        ),
        (
            ReadinessRequest(
                evaluated_at=NOW,
                submission_deadline=FUTURE,
                eligibility=EligibilityRule(
                    minimum_age=18,
                    requires_student=True,
                    allowed_regions=["global"],
                ),
                user=UserContext(age=21, student_status=True, country="Indonesia"),
            ),
            ReadinessStatus.READY_TO_EVALUATE,
        ),
    ],
)
def test_triage_acceptance_cases(
    request: ReadinessRequest,
    expected: ReadinessStatus,
) -> None:
    assert evaluate_readiness(request).status == expected
