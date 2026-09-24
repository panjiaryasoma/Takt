"""Reconciliation and canonical report assembly exports."""

from engine.reconciliation.assembly_policy import (
    CANONICAL_V1,
    CanonicalAssemblyPolicy,
)
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
from engine.reconciliation.service import (
    CanonicalReportAssemblyResult,
    assemble_canonical_report,
    material_fingerprint,
)

__all__ = [
    "CANONICAL_V1",
    "AuthorityDescriptor",
    "CandidateObservation",
    "CanonicalAssemblyPolicy",
    "CanonicalReportAssemblyResult",
    "FieldReconciliationResult",
    "FreshnessDescriptor",
    "ReconciliationInputError",
    "ScopeDescriptor",
    "ScopeRelation",
    "UnusableNormalizedValue",
    "assemble_canonical_report",
    "collect_candidate_observations",
    "comparison_value",
    "intersect_scopes",
    "material_fingerprint",
    "parse_authority",
    "parse_freshness",
    "parse_scope",
    "reconcile_field",
    "scope_relation",
    "source_supersedes",
]
