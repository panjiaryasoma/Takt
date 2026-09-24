"""Internal models for deterministic field-level reconciliation."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from typing import Any

from packages.contracts import (
    CandidateField,
    CanonicalField,
    EvidenceSpan,
    ExtractionPath,
    SourceRecord,
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
    """Minimal internal interpretation of candidate scope metadata."""

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
class ComparisonValue:
    """Stable semantic key plus deterministic canonical representation."""

    key: str
    canonical: Any


@dataclass(frozen=True, slots=True)
class CandidateObservation:
    """A candidate bound back to its source, report identity, and evidence."""

    source_id: str
    report_key: tuple[str, ExtractionPath]
    source_record: SourceRecord
    field: CandidateField
    evidence: tuple[EvidenceSpan, ...]


@dataclass(frozen=True, slots=True)
class FieldReconciliationResult:
    """Internal decision trace around the public CanonicalField contract."""

    canonical_field: CanonicalField
    resolution_basis: tuple[str, ...]
    supporting_source_ids: tuple[str, ...]
    superseded_source_ids: tuple[str, ...] = ()
