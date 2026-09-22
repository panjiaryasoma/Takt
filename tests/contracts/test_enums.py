from packages.contracts.enums import (
    CanonicalFieldState,
    CommitmentType,
    FeasibilityStatus,
    ReadinessStatus,
    RecommendationAction,
)


def _values(enum_type: type) -> list[str]:
    return [member.value for member in enum_type]


def test_readiness_status_contract_is_locked() -> None:
    assert _values(ReadinessStatus) == [
        "READY_TO_EVALUATE",
        "NEEDS_REVIEW",
        "ELIGIBILITY_BLOCKED",
        "DEADLINE_PASSED",
        "INSUFFICIENT_INFORMATION",
    ]


def test_feasibility_status_contract_is_locked() -> None:
    assert _values(FeasibilityStatus) == [
        "FEASIBLE",
        "FEASIBLE_WITH_TRADEOFFS",
        "TIGHT_CAPACITY",
        "NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS",
    ]


def test_commitment_type_contract_is_locked() -> None:
    assert _values(CommitmentType) == ["FIXED", "FLEXIBLE"]


def test_canonical_field_state_contract_is_locked() -> None:
    assert _values(CanonicalFieldState) == [
        "VERIFIED",
        "SINGLE_SOURCE",
        "CONFLICT",
        "MISSING",
        "UNVERIFIED",
    ]


def test_recommendation_action_contract_is_locked() -> None:
    assert _values(RecommendationAction) == [
        "ACCEPT",
        "CHOOSE_ALTERNATIVE",
        "EDIT_CONSTRAINTS",
        "IGNORE",
    ]
