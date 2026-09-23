"""Kontrak source, evidence, candidate extraction, dan canonical report Takt.

Model di file ini mengikuti SOURCE_SCHEMA v1.0 dan domain rules aktif.
Blok ini hanya mendefinisikan bentuk data dan invariant kontrak. Fetching,
parsing, OCR, dan reconciliation algorithm tetap berada di layer engine pada
blok berikutnya.
"""

from __future__ import annotations

from typing import Annotated, Any

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    model_validator,
)

from packages.contracts.enums import CanonicalFieldState, ExtractionPath, SourceType

NonEmptyStr = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1),
]

CORE_CANONICAL_FIELDS = frozenset(
    {
        "competition_name",
        "organizer",
        "submission_deadline",
        "registration_deadline",
        "eligibility",
        "team_size",
        "format",
        "location",
        "tracks_or_categories",
        "deliverables",
        "required_technologies",
        "judging_criteria",
        "prizes_or_benefits",
    }
)

UNRESOLVED_CANONICAL_STATES = frozenset(
    {
        CanonicalFieldState.CONFLICT,
        CanonicalFieldState.MISSING,
        CanonicalFieldState.UNVERIFIED,
    }
)


class ContractModel(BaseModel):
    """Base model kontrak yang menolak field asing secara eksplisit."""

    model_config = ConfigDict(extra="forbid")


class SourceRecord(ContractModel):
    """Snapshot source sesuai required fields SOURCE_SCHEMA v1.0."""

    source_id: NonEmptyStr
    source_type: SourceType
    url_or_document_id: NonEmptyStr
    retrieved_at: AwareDatetime
    content_hash: NonEmptyStr
    authority_rank: Any
    scope: Any
    freshness_metadata: Any

    @model_validator(mode="after")
    def validate_required_metadata_is_explicit(self) -> SourceRecord:
        for field_name in ("authority_rank", "scope", "freshness_metadata"):
            if getattr(self, field_name) is None:
                raise ValueError(
                    f"{field_name} must be explicit and must not be null"
                )
        return self


class EvidenceSpan(ContractModel):
    """Evidence locator yang mengikat sebuah field kembali ke source."""

    evidence_id: NonEmptyStr
    source_id: NonEmptyStr
    page_or_locator: Any
    raw_text_or_visual_reference: Any
    field_name: NonEmptyStr
    extraction_path: ExtractionPath
    extractor_version: NonEmptyStr

    @model_validator(mode="after")
    def validate_required_references(self) -> EvidenceSpan:
        if self.page_or_locator is None:
            raise ValueError("page_or_locator must not be null")
        if self.raw_text_or_visual_reference is None:
            raise ValueError("raw_text_or_visual_reference must not be null")
        return self


class CandidateField(ContractModel):
    """Candidate field hasil extraction sebelum reconciliation."""

    field_name: NonEmptyStr
    raw_value: Any
    normalized_value: Any
    evidence_ids: list[NonEmptyStr] = Field(min_length=1)
    extraction_path: ExtractionPath
    confidence: float | None = Field(default=None, ge=0.0, le=1.0)
    scope: Any

    @model_validator(mode="after")
    def validate_candidate_extraction_path(self) -> CandidateField:
        if self.extraction_path is ExtractionPath.MANUAL:
            raise ValueError(
                "candidate extraction_path must be native, ocr, or vision"
            )
        if self.scope is None:
            raise ValueError("candidate scope must be explicit and must not be null")
        if len(self.evidence_ids) != len(set(self.evidence_ids)):
            raise ValueError("candidate evidence_ids must be unique")
        return self


class CandidateExtractionReport(ContractModel):
    """Candidate report per source/path sebelum reconciliation.

    EvidenceSpan disimpan bersama report supaya setiap evidence_id yang dipakai
    candidate benar-benar dapat ditelusuri kembali ke source dan locator.
    """

    source_id: NonEmptyStr
    extraction_path: ExtractionPath
    fields: list[CandidateField] = Field(default_factory=list)
    evidence: list[EvidenceSpan] = Field(default_factory=list)

    @model_validator(mode="after")
    def validate_report_provenance(self) -> CandidateExtractionReport:
        if self.extraction_path is ExtractionPath.MANUAL:
            raise ValueError(
                "candidate report extraction_path must be native, ocr, or vision"
            )

        field_names = [field.field_name for field in self.fields]
        if len(field_names) != len(set(field_names)):
            raise ValueError("candidate report field_name values must be unique")

        evidence_by_id: dict[str, EvidenceSpan] = {}
        for evidence in self.evidence:
            if evidence.evidence_id in evidence_by_id:
                raise ValueError("candidate report evidence_id values must be unique")
            if evidence.source_id != self.source_id:
                raise ValueError("evidence source_id must match candidate report source_id")
            if evidence.extraction_path is not self.extraction_path:
                raise ValueError(
                    "evidence extraction_path must match candidate report extraction_path"
                )
            evidence_by_id[evidence.evidence_id] = evidence

        for field in self.fields:
            if field.extraction_path is not self.extraction_path:
                raise ValueError(
                    "candidate field extraction_path must match report extraction_path"
                )
            for evidence_id in field.evidence_ids:
                evidence = evidence_by_id.get(evidence_id)
                if evidence is None:
                    raise ValueError(
                        f"candidate evidence_id {evidence_id!r} is not present in report evidence"
                    )
                if evidence.field_name != field.field_name:
                    raise ValueError(
                        "candidate evidence field_name must match candidate field_name"
                    )

        return self


class CanonicalField(ContractModel):
    """Field hasil reconciliation yang mempertahankan candidate dan provenance."""

    field_name: NonEmptyStr
    state: CanonicalFieldState
    value: Any = None
    normalized_value: Any = None
    candidates: list[CandidateField] = Field(default_factory=list)
    evidence_ids: list[NonEmptyStr] = Field(default_factory=list)

    @model_validator(mode="after")
    def validate_state_contract(self) -> CanonicalField:
        if len(self.evidence_ids) != len(set(self.evidence_ids)):
            raise ValueError("canonical evidence_ids must be unique")

        if any(candidate.field_name != self.field_name for candidate in self.candidates):
            raise ValueError(
                "all canonical candidates must have the same field_name as the canonical field"
            )

        candidate_evidence_ids = {
            evidence_id
            for candidate in self.candidates
            for evidence_id in candidate.evidence_ids
        }
        missing_provenance = candidate_evidence_ids.difference(self.evidence_ids)
        if missing_provenance:
            raise ValueError(
                "canonical evidence_ids must retain every candidate evidence_id"
            )

        if self.state in {
            CanonicalFieldState.VERIFIED,
            CanonicalFieldState.SINGLE_SOURCE,
        }:
            if self.value is None or self.normalized_value is None:
                raise ValueError(
                    f"{self.state.value} canonical field requires a usable value"
                )
            if not self.candidates or not self.evidence_ids:
                raise ValueError(
                    f"{self.state.value} canonical field requires candidate provenance"
                )

        elif self.state is CanonicalFieldState.CONFLICT:
            if self.value is not None or self.normalized_value is not None:
                raise ValueError("CONFLICT canonical field must not expose a usable value")
            if len(self.candidates) < 2:
                raise ValueError("CONFLICT canonical field requires at least two candidates")
            if len(self.evidence_ids) < 2:
                raise ValueError(
                    "CONFLICT canonical field requires at least two evidence references"
                )

            first = self.candidates[0]
            has_normalized_disagreement = any(
                candidate.normalized_value != first.normalized_value
                for candidate in self.candidates[1:]
            )
            if not has_normalized_disagreement:
                raise ValueError(
                    "CONFLICT canonical field requires normalized candidate disagreement"
                )

        elif self.state is CanonicalFieldState.MISSING:
            if self.value is not None or self.normalized_value is not None:
                raise ValueError("MISSING canonical field must not expose a usable value")
            if self.candidates:
                raise ValueError("MISSING canonical field must not contain candidates")

        elif self.state is CanonicalFieldState.UNVERIFIED:
            if self.value is not None or self.normalized_value is not None:
                raise ValueError("UNVERIFIED canonical field must not expose a usable value")
            if not self.candidates or not self.evidence_ids:
                raise ValueError(
                    "UNVERIFIED canonical field requires candidate provenance"
                )

        return self


class CanonicalCompetitionReport(ContractModel):
    """Versioned canonical representation untuk satu evidence snapshot."""

    competition_id: NonEmptyStr
    report_version: int = Field(ge=1)
    source_ids: list[NonEmptyStr] = Field(min_length=1)
    canonical_fields: dict[str, CanonicalField]
    unresolved_critical_fields: list[NonEmptyStr] = Field(default_factory=list)

    @model_validator(mode="after")
    def validate_report_contract(self) -> CanonicalCompetitionReport:
        if len(self.source_ids) != len(set(self.source_ids)):
            raise ValueError("source_ids must be unique")
        if len(self.unresolved_critical_fields) != len(
            set(self.unresolved_critical_fields)
        ):
            raise ValueError("unresolved_critical_fields must be unique")

        mismatched = [
            key
            for key, field in self.canonical_fields.items()
            if key != field.field_name
        ]
        if mismatched:
            raise ValueError(
                "canonical_fields keys must match each CanonicalField.field_name"
            )

        missing_core_fields = CORE_CANONICAL_FIELDS.difference(self.canonical_fields)
        if missing_core_fields:
            raise ValueError(
                "canonical_fields must represent every SOURCE_SCHEMA core field; "
                f"missing: {', '.join(sorted(missing_core_fields))}"
            )

        for field_name in self.unresolved_critical_fields:
            field = self.canonical_fields.get(field_name)
            if field is None:
                raise ValueError(
                    "unresolved_critical_fields must reference a canonical field"
                )
            if field.state not in UNRESOLVED_CANONICAL_STATES:
                raise ValueError(
                    "unresolved critical field must be CONFLICT, MISSING, or UNVERIFIED"
                )

        return self
