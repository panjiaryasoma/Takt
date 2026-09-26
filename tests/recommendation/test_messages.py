from __future__ import annotations

import pytest

from engine.recommendation.messages import (
    RecommendationEvidenceError,
    render_rationale,
    render_tradeoffs,
)


# REC-010
def test_known_reason_and_sensitivity_codes_render_deterministically() -> None:
    assert render_rationale(
        ("REQUIRED_MAX_INFEASIBLE",),
        ("EFFORT_OVERRUN_BREAKS_PLAN",),
    ) == (
        "Required work no longer fits at the maximum effort estimate.",
        "The current plan is sensitive to effort overruns.",
    )


# REC-003
def test_known_tradeoff_code_renders_deterministically() -> None:
    assert render_tradeoffs(("OPTIONAL_SCOPE_DOES_NOT_FIT",)) == (
        "Some optional tasks would need to be dropped under the current constraints.",
    )


# REC-011
@pytest.mark.parametrize(
    ("reason_codes", "sensitivity_codes", "tradeoff_codes"),
    (
        (("UNKNOWN_REASON",), (), ()),
        ((), ("UNKNOWN_SENSITIVITY",), ()),
        ((), (), ("UNKNOWN_TRADEOFF",)),
    ),
)
def test_unknown_evidence_code_is_rejected(
    reason_codes,
    sensitivity_codes,
    tradeoff_codes,
) -> None:
    with pytest.raises(RecommendationEvidenceError):
        render_rationale(reason_codes, sensitivity_codes)
        render_tradeoffs(tradeoff_codes)
