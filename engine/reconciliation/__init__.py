"""Field-level reconciliation for source extraction candidates."""

from engine.reconciliation.field_reconciler import (
    collect_candidate_observations,
    reconcile_field,
)
from engine.reconciliation.models import (
    CandidateObservation,
    FieldReconciliationResult,
    ReconciliationInputError,
    ScopeDescriptor,
    ScopeRelation,
)
from engine.reconciliation.policy import (
    UnusableNormalizedValue,
    comparison_value,
    parse_scope,
    scope_relation,
    source_supersedes,
)

__all__ = [
    "CandidateObservation",
    "FieldReconciliationResult",
    "ReconciliationInputError",
    "ScopeDescriptor",
    "ScopeRelation",
    "UnusableNormalizedValue",
    "collect_candidate_observations",
    "comparison_value",
    "parse_scope",
    "reconcile_field",
    "scope_relation",
    "source_supersedes",
]
