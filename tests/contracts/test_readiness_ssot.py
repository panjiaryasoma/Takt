from datetime import UTC, datetime, timedelta

from engine.triage.service import evaluate_readiness
from packages.contracts import ReadinessStatus, ReadinessTriage
from packages.contracts.triage import ReadinessRequest, UserContext


def test_engine_returns_canonical_readiness_triage() -> None:
    now = datetime(2026, 9, 22, 8, 0, tzinfo=UTC)
    result = evaluate_readiness(
        ReadinessRequest(
            evaluated_at=now,
            submission_deadline=now + timedelta(days=1),
            user=UserContext(age=21),
        )
    )

    assert type(result) is ReadinessTriage
    assert result.status is ReadinessStatus.READY_TO_EVALUATE
