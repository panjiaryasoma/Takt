"""Internal models for deterministic field-level reconciliation."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from typing import Any

from packages.contracts import (
    CandidateField,
    CanonicalField,
    EvidenceSpan,
    ExtractionPath,
    SourceRecord,
    SourceType,
)


class ReconciliationInputError(ValueError):
    """Raised when reconciliation input breaks provenance/linkage invariants."""


class ScopeRelation(StrEnum):
    """Relationship between two explicitly modeled candidate scopes."""

    SAME = "SAME"
    OVERLAPS = "OVERLAPS"
    DISJOINT = "DISJOINT"
    UNKNOWN = "UNKNOWN"


@dataclass(frozen=True, slots=True)
class ScopeDescriptor:
    """Minimal internal interpretation of applicability metadata."""

    audience: str | None = None
    category: str | None = None
    region: str | None = None
    known: bool = True

    @property
    def key(self) -> tuple[str | None, str | None, str | None]:
        return (self.audience, self.category, self.region)

    def as_mapping(self) -> dict[str, str | None]:
        return {
            "audience": self.audience,
            "category": self.category,
            "region": self.region,
        }


@dataclass(frozen=True, slots=True)
class AuthorityDescriptor:
    """Validated contextual authority metadata for one source."""

    source_type: SourceType
    basis: str | None
    tier: int | None = None

    @property
    def known(self) -> bool:
        return self.basis is not None


@dataclass(frozen=True, slots=True)
class FreshnessDescriptor:
    """Validated source freshness/update metadata."""

    effective_at: datetime | None
    supersedes_source_ids: tuple[str, ...] = ()
    update_kind: str | None = None
    applies_to_fields: tuple[str, ...] = ()

    @property
    def known(self) -> bool:
        return self.effective_at is not None


@dataclass(frozen=True, slots=True)
class ComparisonValue:
    """Stable semantic key plus deterministic canonical representation."""

    key: str
    canonical: Any


@dataclass(frozen=True, slots=True)
class CandidateObservation:
    """A candidate bound back to source metadata and evidence."""

    source_id: str
    report_key: tuple[str, ExtractionPath, str]
    source_record: SourceRecord
    field: CandidateField
    evidence: tuple[EvidenceSpan, ...]
    source_scope: ScopeDescriptor
    candidate_scope: ScopeDescriptor
    effective_scope: ScopeDescriptor
    authority: AuthorityDescriptor
    freshness: FreshnessDescriptor


@dataclass(frozen=True, slots=True)
class FieldReconciliationResult:
    """Internal decision trace around the public CanonicalField contract."""

    canonical_field: CanonicalField
    resolution_basis: tuple[str, ...]
    supporting_source_ids: tuple[str, ...]
    superseded_source_ids: tuple[str, ...] = ()
