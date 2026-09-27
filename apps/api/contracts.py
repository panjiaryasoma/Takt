"""Strict public API contracts for Issue 4A integration."""

from __future__ import annotations

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

from packages.contracts import (
    AvailabilityInput,
    CanonicalCompetitionReport,
    FeasibilityStatus,
    ReadinessStatus,
    ReadinessTriage,
    Recommendation,
    RecommendationAction,
    SourceRecord,
    SourceType,
    EvidenceSpan,
    ExtractionPath,
    UserContext,
    WorkloadInput,
)

DOMAIN_SCHEMA_VERSION = "3.0.0"
RECONCILIATION_POLICY_VERSION = "reconciliation-v1"
ASSEMBLY_POLICY_VERSION = "canonical-v1"
REPORT_WIRE_FINGERPRINT_VERSION = "report-wire-jcs-sha256-v1"
EVALUATION_BASIS_VERSION = "evaluation-basis-v1"
READINESS_BASIS_VERSION = "readiness-basis-v1"
READINESS_PROJECTION_VERSION = "readiness-projection-v1"
PLANNING_BASIS_VERSION = "planning-basis-v1"
PLANNING_POLICY_VERSION = "planning-policy-v1"
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
    domain_schema_version: Literal["3.0.0"] = DOMAIN_SCHEMA_VERSION
    competition_id: NonEmptyStr
    report_version: StrictInt = Field(ge=1)
    reconciliation_policy_version: NonEmptyStr = RECONCILIATION_POLICY_VERSION
    assembly_policy_version: NonEmptyStr = ASSEMBLY_POLICY_VERSION
    assembly_material_fingerprint: NonEmptyStr
    wire_fingerprint_version: NonEmptyStr = REPORT_WIRE_FINGERPRINT_VERSION
    wire_fingerprint: NonEmptyStr


class CanonicalReportBundleV1(ApiModel):
    report: CanonicalCompetitionReport
    ref: CanonicalReportRefV1


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


class RecommendationSetV1(ApiModel):
    primary_candidate: CandidateRefV1
    alternative_candidates: tuple[CandidateRefV1, ...] = ()
    recommendation: Recommendation
    allowed_actions: tuple[RecommendationAction, ...]

    @model_validator(mode="after")
    def validate_candidate_refs(self) -> RecommendationSetV1:
        alternative_ids = tuple(item.candidate_id for item in self.alternative_candidates)
        if len(set(alternative_ids)) != len(alternative_ids):
            raise ValueError("alternative candidate references must be unique")
        if self.primary_candidate.candidate_id in alternative_ids:
            raise ValueError("primary candidate must not appear in alternatives")
        if any(
            item.evaluation_id != self.primary_candidate.evaluation_id
            for item in self.alternative_candidates
        ):
            raise ValueError("all public candidate references must share one evaluation_id")
        return self


class PlanningDecisionV1(ApiModel):
    feasibility: FeasibilityStatus
    reason_codes: tuple[NonEmptyStr, ...] = ()
    tradeoff_codes: tuple[NonEmptyStr, ...] = ()
    sensitivity_codes: tuple[NonEmptyStr, ...] = ()
    recommendation: RecommendationSetV1 | None

    @model_validator(mode="after")
    def validate_recommendation_presence(self) -> PlanningDecisionV1:
        is_infeasible = (
            self.feasibility
            is FeasibilityStatus.NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS
        )
        if is_infeasible and self.recommendation is not None:
            raise ValueError("infeasible planning decision must not contain recommendation")
        if not is_infeasible and self.recommendation is None:
            raise ValueError("recommendable planning decision requires recommendation")
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
        recommendation = self.planning.recommendation
        if recommendation is not None:
            if recommendation.primary_candidate.evaluation_id != self.evaluation_id:
                raise ValueError("candidate reference evaluation_id must match response")
        return self


class ApiErrorDetailV1(ApiModel):
    path: NonEmptyStr
    message: NonEmptyStr
    type: NonEmptyStr | None = None


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


class CompetitionAnalyzeUrlRequestV1(ApiModel):
    competition_id: NonEmptyStr
    url: NonEmptyStr
    source: SourceMetadataV1
    previous_report_bundle: CanonicalReportBundleV1 | None = None


class CompetitionAnalyzePdfMetadataV1(ApiModel):
    competition_id: NonEmptyStr
    document_id: NonEmptyStr
    source: SourceMetadataV1
    previous_report_bundle: CanonicalReportBundleV1 | None = None


class ExtractionRunAuditV1(ApiModel):
    source_id: NonEmptyStr
    snapshot_id: NonEmptyStr
    extraction_path: ExtractionPath
    extractor_version: NonEmptyStr


class AnalysisProvenanceV1(ApiModel):
    sources: tuple[SourceRecord, ...]
    extraction_runs: tuple[ExtractionRunAuditV1, ...]
    evidence: tuple[EvidenceSpan, ...]


class CompetitionAnalyzeResponseV1(ApiModel):
    report_bundle: CanonicalReportBundleV1
    provenance: AnalysisProvenanceV1
    report_changed: StrictBool
