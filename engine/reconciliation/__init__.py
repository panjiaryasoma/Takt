"""Field-level reconciliation for source extraction candidates."""

from engine.reconciliation.field_reconciler import (
    collect_candidate_observations,
    reconcile_field,
)
from engine.reconciliation.models import (
    AuthorityDescriptor,
    CandidateObservation,
    FieldReconciliationResult,
    FreshnessDescriptor,
    ReconciliationInputError,
    ScopeDescriptor,
    ScopeRelation,
)
from engine.reconciliation.policy import (
    UnusableNormalizedValue,
    comparison_value,
    intersect_scopes,
    parse_authority,
    parse_freshness,
    parse_scope,
    scope_relation,
    source_supersedes,
)

__all__ = [
    "AuthorityDescriptor",
    "CandidateObservation",
    "FieldReconciliationResult",
    "FreshnessDescriptor",
    "ReconciliationInputError",
    "ScopeDescriptor",
    "ScopeRelation",
    "UnusableNormalizedValue",
    "collect_candidate_observations",
    "comparison_value",
    "intersect_scopes",
    "parse_authority",
    "parse_freshness",
    "parse_scope",
    "reconcile_field",
    "scope_relation",
    "source_supersedes",
]
