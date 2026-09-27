"""Policy version strings must point to explicit material-behavior authority."""

from apps.api.contracts import (
    PLANNING_POLICY_VERSION,
    READINESS_PROJECTION_VERSION,
    RECONCILIATION_POLICY_VERSION,
)
from apps.api.policy_versions import (
    PLANNING_POLICY,
    READINESS_PROJECTION_POLICY,
    RECONCILIATION_POLICY,
)


def test_public_policy_versions_have_explicit_authority() -> None:
    assert RECONCILIATION_POLICY_VERSION == RECONCILIATION_POLICY.version
    assert READINESS_PROJECTION_VERSION == READINESS_PROJECTION_POLICY.version
    assert PLANNING_POLICY_VERSION == PLANNING_POLICY.version

    assert "multi-source candidate reconciliation" in (
        RECONCILIATION_POLICY.material_behaviors
    )
    assert "canonical eligibility scope resolution" in (
        READINESS_PROJECTION_POLICY.material_behaviors
    )
    assert "LIKELY public recommendation candidate pool" in (
        PLANNING_POLICY.material_behaviors
    )
    assert "recommendation assembly and allowed actions" in (
        PLANNING_POLICY.material_behaviors
    )
