"""Strict public API contracts for Issue 4A integration."""

from __future__ import annotations

import hmac
from typing import Annotated, Any, Literal
from uuid import UUID

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    StrictBool,
    StrictInt,
    StringConstraints,
    model_validator,
)

from pydantic_core import PydanticCustomError

from apps.api.canonical_json import CanonicalJsonError, jcs_sha256
from apps.api.policy_versions import (
    PLANNING_POLICY,
    READINESS_PROJECTION_POLICY,
    RECONCILIATION_POLICY,
)
from packages.contracts import (
    AllocationBlock,
    AvailabilityInput,
    CandidateExtractionReport,
    CanonicalCompetitionReport,
    FeasibilityStatus,
    ReadinessStatus,
    ReadinessTriage,
    RecommendationAction,
    SourceRecord,
    SourceType,
    EvidenceSpan,
    ExtractionPath,
    UserContext,
    WorkloadInput,
)

DOMAIN_SCHEMA_VERSION = "3.0.0"
RECONCILIATION_POLICY_VERSION = RECONCILIATION_POLICY.version
ASSEMBLY_POLICY_VERSION = "canonical-v1"
REPORT_WIRE_FINGERPRINT_VERSION = "report-wire-jcs-sha256-v1"
SOURCE_SET_FINGERPRINT_VERSION = "source-set-jcs-sha256-v1"
EVALUATION_BASIS_VERSION = "evaluation-basis-v1"
READINESS_BASIS_VERSION = "readiness-basis-v1"
READINESS_PROJECTION_VERSION = READINESS_PROJECTION_POLICY.version
PLANNING_BASIS_VERSION = "planning-basis-v1"
PLANNING_POLICY_VERSION = PLANNING_POLICY.version
SOLVER_BACKEND = "ortools-cp-sat"

NonEmptyStr = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, strict=True),
]
Sha256Hex = Annotated[
    str,
    StringConstraints(pattern=r"^[0-9a-f]{64}$", strict=True),
]


class ApiModel(BaseModel):
    """Wire model that rejects unknown fields instead of silently ignoring them."""

    model_config = ConfigDict(extra="forbid", frozen=True, validate_default=True)


class CanonicalReportRefV1(ApiModel):
    domain_schema_version: NonEmptyStr = DOMAIN_SCHEMA_VERSION
    competition_id: NonEmptyStr
    report_version: StrictInt = Field(ge=1)
    reconciliation_policy_version: NonEmptyStr = RECONCILIATION_POLICY_VERSION
    assembly_policy_version: NonEmptyStr = ASSEMBLY_POLICY_VERSION
    assembly_material_fingerprint: Sha256Hex
    source_set_fingerprint_version: NonEmptyStr = SOURCE_SET_FINGERPRINT_VERSION
    source_set_fingerprint: Sha256Hex | None = None
    wire_fingerprint_version: NonEmptyStr = REPORT_WIRE_FINGERPRINT_VERSION
    wire_fingerprint: Sha256Hex


class CanonicalReportBundleV1(ApiModel):
    report: CanonicalCompetitionReport
    ref: CanonicalReportRefV1

    @model_validator(mode="before")
    @classmethod
    def verify_raw_wire_bundle(cls, value: Any) -> Any:
        """Verify raw parsed JSON before Pydantic can coerce wire values."""

        if not isinstance(value, dict):
            return value
        report = value.get("report")
        ref = value.get("ref")
        if not isinstance(report, dict) or not isinstance(ref, dict):
            return value

        supported = {
            "domain_schema_version": DOMAIN_SCHEMA_VERSION,
            "reconciliation_policy_version": RECONCILIATION_POLICY_VERSION,
            "assembly_policy_version": ASSEMBLY_POLICY_VERSION,
            "source_set_fingerprint_version": SOURCE_SET_FINGERPRINT_VERSION,
            "wire_fingerprint_version": REPORT_WIRE_FINGERPRINT_VERSION,
        }
        actual = {key: ref.get(key) for key in supported}
        if actual != supported:
            raise PydanticCustomError(
                "unsupported_report_contract",
                "Canonical report contract or policy version is not supported.",
            )

        if ref.get("competition_id") != report.get("competition_id"):
            raise PydanticCustomError(
                "report_bundle_invalid",
                "Canonical report reference competition_id does not match report.",
            )
        if ref.get("report_version") != report.get("report_version"):
            raise PydanticCustomError(
                "report_bundle_invalid",
                "Canonical report reference report_version does not match report.",
            )

        wire_fingerprint = ref.get("wire_fingerprint")
        assembly_fingerprint = ref.get("assembly_material_fingerprint")
        source_set_fingerprint = ref.get("source_set_fingerprint")
        fingerprints = [wire_fingerprint, assembly_fingerprint]
        if source_set_fingerprint is not None:
            fingerprints.append(source_set_fingerprint)
        for fingerprint in fingerprints:
            if (
                not isinstance(fingerprint, str)
                or len(fingerprint) != 64
                or fingerprint != fingerprint.lower()
            ):
                raise PydanticCustomError(
                    "report_bundle_invalid",
                    "Canonical report bundle contains an invalid fingerprint.",
                )
            try:
                int(fingerprint, 16)
            except ValueError as exc:
                raise PydanticCustomError(
                    "report_bundle_invalid",
                    "Canonical report bundle contains an invalid fingerprint.",
                ) from exc

        ref_material = dict(ref)
        ref_material.pop("wire_fingerprint", None)
        try:
            expected = jcs_sha256({"report": report, "ref": ref_material})
        except CanonicalJsonError as exc:
            raise PydanticCustomError(
                "report_bundle_invalid",
                "Canonical report bundle cannot be canonicalized.",
            ) from exc
        if not hmac.compare_digest(expected, wire_fingerprint):
            raise PydanticCustomError(
                "report_bundle_invalid",
                "Canonical report bundle failed wire fingerprint validation.",
            )
        return value


class ReadinessUserContextV1(ApiModel):
    age: StrictInt | None = Field(default=None, ge=0)
    student_status: StrictBool | None = None
    country: NonEmptyStr | None = None

    def to_domain(self) -> UserContext:
        return UserContext(
            age=self.age,
            student_status=self.student_status,
            country=self.country,
        )


class ReadinessContextV1(ApiModel):
    """User-controlled readiness context.

    evaluated_at is intentionally absent. Product evaluation uses one server
    clock sample so deadline truth cannot be overridden by the client.
    """

    user: ReadinessUserContextV1
    selected_scope: NonEmptyStr | None = None
    require_technology_information: StrictBool = False


class PlanEvaluatePlanningV1(ApiModel):
    workload: WorkloadInput
    availability: AvailabilityInput


class PlanEvaluateRequestV1(ApiModel):
    report_bundle: CanonicalReportBundleV1
    readiness_context: ReadinessContextV1
    planning: PlanEvaluatePlanningV1


class ReportBasisV1(ApiModel):
    competition_id: NonEmptyStr
    report_version: StrictInt = Field(ge=1)
    reconciliation_policy_version: NonEmptyStr
    assembly_policy_version: NonEmptyStr
    assembly_material_fingerprint: Sha256Hex


class ReadinessBasisV1(ApiModel):
    basis_version: Literal["readiness-basis-v1"] = READINESS_BASIS_VERSION
    basis_fingerprint: Sha256Hex
    projection_version: Literal["readiness-projection-v1"] = READINESS_PROJECTION_VERSION
    rule_version: NonEmptyStr


class PlanningBasisV1(ApiModel):
    basis_version: Literal["planning-basis-v1"] = PLANNING_BASIS_VERSION
    basis_fingerprint: Sha256Hex
    policy_version: Literal["planning-policy-v1"] = PLANNING_POLICY_VERSION
    solver_backend: Literal["ortools-cp-sat"] = SOLVER_BACKEND
    solver_backend_version: NonEmptyStr


class EvaluationBasisV1(ApiModel):
    version: Literal["evaluation-basis-v1"] = EVALUATION_BASIS_VERSION
    domain_schema_version: Literal["3.0.0"] = DOMAIN_SCHEMA_VERSION
    fingerprint: Sha256Hex
    report: ReportBasisV1
    readiness: ReadinessBasisV1
    planning: PlanningBasisV1 | None = None


class CandidateRefV1(ApiModel):
    evaluation_id: UUID
    candidate_id: NonEmptyStr


class RecommendedNextWorkV1(ApiModel):
    task_id: NonEmptyStr
    task_name: NonEmptyStr
    start: AwareDatetime
    end: AwareDatetime
    allocated_minutes: StrictInt = Field(gt=0)
    availability_source: NonEmptyStr


class SuggestedWorkWindowV1(ApiModel):
    task_id: NonEmptyStr
    start: AwareDatetime
    end: AwareDatetime
    allocated_minutes: StrictInt = Field(gt=0)
    availability_source: NonEmptyStr


class RecommendationAlternativeV1(ApiModel):
    candidate_id: NonEmptyStr
    buffer_minutes: StrictInt = Field(ge=0)
    recommended_next_work: RecommendedNextWorkV1 | None
    suggested_windows: tuple[SuggestedWorkWindowV1, ...]
    tradeoffs: tuple[NonEmptyStr, ...]


class RecommendationAssumptionV1(ApiModel):
    task_id: NonEmptyStr | None = None
    description: NonEmptyStr


class RecommendationV1(ApiModel):
    recommended_candidate_id: NonEmptyStr
    recommended_next_work: RecommendedNextWorkV1 | None
    suggested_windows: tuple[SuggestedWorkWindowV1, ...]
    alternatives: tuple[RecommendationAlternativeV1, ...] = ()
    rationale: tuple[NonEmptyStr, ...]
    tradeoffs: tuple[NonEmptyStr, ...]
    assumptions: tuple[RecommendationAssumptionV1, ...]


class PublicCandidateV1(ApiModel):
    ref: CandidateRefV1
    work_blocks: tuple[AllocationBlock, ...]
    buffer_minutes: StrictInt = Field(ge=0)
    assumptions: tuple[NonEmptyStr, ...] = ()


class RecommendationTraceV1(ApiModel):
    competition_id: NonEmptyStr
    report_version: StrictInt = Field(ge=1)
    assembly_material_fingerprint: Sha256Hex
    evaluation_basis_fingerprint: Sha256Hex
    planning_basis_fingerprint: Sha256Hex
    planning_policy_version: Literal["planning-policy-v1"] = PLANNING_POLICY_VERSION


class RecommendationSetV1(ApiModel):
    primary_candidate: CandidateRefV1
    alternative_candidates: tuple[CandidateRefV1, ...] = ()
    recommendation: RecommendationV1
    trace: RecommendationTraceV1

    @model_validator(mode="after")
    def validate_candidate_refs(self) -> RecommendationSetV1:
        alternative_ids = tuple(
            item.candidate_id for item in self.alternative_candidates
        )
        if len(set(alternative_ids)) != len(alternative_ids):
            raise ValueError("alternative candidate references must be unique")
        if self.primary_candidate.candidate_id in alternative_ids:
            raise ValueError("primary candidate must not appear in alternatives")
        if any(
            item.evaluation_id != self.primary_candidate.evaluation_id
            for item in self.alternative_candidates
        ):
            raise ValueError(
                "all public candidate references must share one evaluation_id"
            )
        if (
            self.recommendation.recommended_candidate_id
            != self.primary_candidate.candidate_id
        ):
            raise ValueError(
                "recommendation primary candidate ID must match public candidate reference"
            )
        payload_alternative_ids = tuple(
            item.candidate_id for item in self.recommendation.alternatives
        )
        if payload_alternative_ids != alternative_ids:
            raise ValueError(
                "recommendation alternative IDs must match public candidate references"
            )
        return self


class PlanningDecisionV1(ApiModel):
    feasibility: FeasibilityStatus
    candidates: tuple[PublicCandidateV1, ...]
    allowed_actions: tuple[RecommendationAction, ...]
    reason_codes: tuple[NonEmptyStr, ...] = ()
    tradeoff_codes: tuple[NonEmptyStr, ...] = ()
    sensitivity_codes: tuple[NonEmptyStr, ...] = ()
    recommendation: RecommendationSetV1 | None

    @model_validator(mode="after")
    def validate_public_decision(self) -> PlanningDecisionV1:
        candidate_ids = tuple(item.ref.candidate_id for item in self.candidates)
        if len(set(candidate_ids)) != len(candidate_ids):
            raise ValueError("public candidate IDs must be unique within one evaluation")
        if len(set(self.allowed_actions)) != len(self.allowed_actions):
            raise ValueError("allowed_actions must not contain duplicates")

        is_infeasible = (
            self.feasibility
            is FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS
        )
        no_recommendation_actions = (
            RecommendationAction.EDIT_CONSTRAINTS,
            RecommendationAction.IGNORE,
        )
        if is_infeasible:
            if self.candidates:
                raise ValueError("infeasible planning decision must not expose candidates")
            if self.recommendation is not None:
                raise ValueError(
                    "infeasible planning decision must not contain recommendation"
                )
            if self.allowed_actions != no_recommendation_actions:
                raise ValueError(
                    "infeasible planning actions must be EDIT_CONSTRAINTS then IGNORE"
                )
            return self

        if not self.candidates:
            raise ValueError("recommendable planning decision requires candidates")
        if self.recommendation is None:
            raise ValueError("recommendable planning decision requires recommendation")

        evaluation_ids = {item.ref.evaluation_id for item in self.candidates}
        if len(evaluation_ids) != 1:
            raise ValueError("all public candidates must share one evaluation_id")

        by_id = {item.ref.candidate_id: item for item in self.candidates}
        refs = (
            self.recommendation.primary_candidate,
            *self.recommendation.alternative_candidates,
        )
        referenced_ids = tuple(item.candidate_id for item in refs)
        if referenced_ids != candidate_ids:
            raise ValueError(
                "recommendation candidate references must resolve to the public "
                "candidate pool in canonical order"
            )
        if any(item.candidate_id not in by_id for item in refs):
            raise ValueError("recommendation references an unknown public candidate")

        expected_actions = (
            RecommendationAction.ACCEPT,
            *(
                (RecommendationAction.CHOOSE_ALTERNATIVE,)
                if self.recommendation.alternative_candidates
                else ()
            ),
            RecommendationAction.EDIT_CONSTRAINTS,
            RecommendationAction.IGNORE,
        )
        if self.allowed_actions != expected_actions:
            raise ValueError(
                "recommendable planning actions must match alternative availability"
            )
        return self


class PlanEvaluateResponseV1(ApiModel):
    evaluation_id: UUID
    evaluated_at: AwareDatetime
    basis: EvaluationBasisV1
    readiness: ReadinessTriage
    planning: PlanningDecisionV1 | None

    @model_validator(mode="after")
    def validate_stage_shape(self) -> PlanEvaluateResponseV1:
        ready = self.readiness.status is ReadinessStatus.READY_TO_EVALUATE
        if not ready:
            if self.planning is not None or self.basis.planning is not None:
                raise ValueError("blocked readiness result must not contain planning state")
            return self

        if self.planning is None or self.basis.planning is None:
            raise ValueError("ready evaluation requires planning state and planning basis")
        for candidate in self.planning.candidates:
            if candidate.ref.evaluation_id != self.evaluation_id:
                raise ValueError(
                    "public candidate evaluation_id must match response"
                )

        recommendation = self.planning.recommendation
        if recommendation is not None:
            if recommendation.primary_candidate.evaluation_id != self.evaluation_id:
                raise ValueError(
                    "candidate reference evaluation_id must match response"
                )
            trace = recommendation.trace
            if trace.competition_id != self.basis.report.competition_id:
                raise ValueError(
                    "recommendation trace competition_id must match evaluation basis"
                )
            if trace.report_version != self.basis.report.report_version:
                raise ValueError(
                    "recommendation trace report_version must match evaluation basis"
                )
            if (
                trace.assembly_material_fingerprint
                != self.basis.report.assembly_material_fingerprint
            ):
                raise ValueError(
                    "recommendation report fingerprint must match evaluation basis"
                )
            if trace.evaluation_basis_fingerprint != self.basis.fingerprint:
                raise ValueError(
                    "recommendation evaluation fingerprint must match evaluation basis"
                )
            if (
                trace.planning_basis_fingerprint
                != self.basis.planning.basis_fingerprint
            ):
                raise ValueError(
                    "recommendation planning fingerprint must match evaluation basis"
                )
            if trace.planning_policy_version != self.basis.planning.policy_version:
                raise ValueError(
                    "recommendation planning policy must match evaluation basis"
                )
        return self


class ApiErrorDetailV1(ApiModel):
    path: NonEmptyStr
    message: NonEmptyStr
    code: NonEmptyStr


class ApiErrorBodyV1(ApiModel):
    code: NonEmptyStr
    message: NonEmptyStr
    stage: NonEmptyStr
    details: tuple[ApiErrorDetailV1, ...] = ()


class ApiErrorResponseV1(ApiModel):
    error: ApiErrorBodyV1


class SourceMetadataV1(ApiModel):
    source_id: NonEmptyStr
    source_type: SourceType
    authority_rank: Any
    scope: Any
    freshness_metadata: Any

    @model_validator(mode="after")
    def validate_explicit_metadata(self) -> SourceMetadataV1:
        for field_name in ("authority_rank", "scope", "freshness_metadata"):
            if getattr(self, field_name) is None:
                raise ValueError(f"{field_name} must be explicit and non-null")
        return self


class ExtractionRunAuditV1(ApiModel):
    source_id: NonEmptyStr
    snapshot_id: NonEmptyStr
    extraction_path: ExtractionPath
    extractor_version: NonEmptyStr


class SourceAnalysisArtifactV1(ApiModel):
    source: SourceRecord
    candidate_reports: tuple[CandidateExtractionReport, ...] = Field(min_length=1)
    extraction_runs: tuple[ExtractionRunAuditV1, ...] = Field(min_length=1)

    @model_validator(mode="after")
    def validate_source_continuity(self) -> SourceAnalysisArtifactV1:
        source_id = self.source.source_id
        if any(item.source_id != source_id for item in self.candidate_reports):
            raise ValueError(
                "candidate report source_id must match source artifact source_id"
            )
        if any(item.source_id != source_id for item in self.extraction_runs):
            raise ValueError(
                "extraction run source_id must match source artifact source_id"
            )
        return self


class CompetitionAnalyzeUrlRequestV1(ApiModel):
    competition_id: NonEmptyStr
    url: NonEmptyStr
    source: SourceMetadataV1
    previous_report_bundle: CanonicalReportBundleV1 | None = None
    prior_source_artifacts: tuple[SourceAnalysisArtifactV1, ...] = ()


class CompetitionAnalyzePdfMetadataV1(ApiModel):
    competition_id: NonEmptyStr
    document_id: NonEmptyStr
    source: SourceMetadataV1
    previous_report_bundle: CanonicalReportBundleV1 | None = None
    prior_source_artifacts: tuple[SourceAnalysisArtifactV1, ...] = ()


class AnalysisProvenanceV1(ApiModel):
    sources: tuple[SourceRecord, ...]
    extraction_runs: tuple[ExtractionRunAuditV1, ...]
    evidence: tuple[EvidenceSpan, ...]


class CompetitionAnalyzeResponseV1(ApiModel):
    report_bundle: CanonicalReportBundleV1
    source_artifacts: tuple[SourceAnalysisArtifactV1, ...]
    provenance: AnalysisProvenanceV1
    report_changed: StrictBool

    @model_validator(mode="after")
    def validate_source_set_traceability(self) -> CompetitionAnalyzeResponseV1:
        artifact_ids = tuple(
            sorted(item.source.source_id for item in self.source_artifacts)
        )
        if len(set(artifact_ids)) != len(artifact_ids):
            raise ValueError("source artifact IDs must be unique")

        report_ids = tuple(sorted(self.report_bundle.report.source_ids))
        provenance_ids = tuple(
            sorted(item.source_id for item in self.provenance.sources)
        )
        if artifact_ids != report_ids or provenance_ids != report_ids:
            raise ValueError(
                "report, source artifacts, and provenance must share one source set"
            )

        available_evidence = {
            item.evidence_id for item in self.provenance.evidence
        }
        referenced_evidence = {
            evidence_id
            for field in self.report_bundle.report.canonical_fields.values()
            for evidence_id in field.evidence_ids
        }
        if not referenced_evidence <= available_evidence:
            raise ValueError(
                "canonical evidence references must resolve in public provenance"
            )
        return self
