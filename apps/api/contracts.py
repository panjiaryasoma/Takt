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
from packages.contracts import (
    AvailabilityInput,
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
    domain_schema_version: NonEmptyStr = DOMAIN_SCHEMA_VERSION
    competition_id: NonEmptyStr
    report_version: StrictInt = Field(ge=1)
    reconciliation_policy_version: NonEmptyStr = RECONCILIATION_POLICY_VERSION
    assembly_policy_version: NonEmptyStr = ASSEMBLY_POLICY_VERSION
    assembly_material_fingerprint: Sha256Hex
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
        for fingerprint in (wire_fingerprint, assembly_fingerprint):
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


class RecommendationSetV1(ApiModel):
    primary_candidate: CandidateRefV1
    alternative_candidates: tuple[CandidateRefV1, ...] = ()
    recommendation: RecommendationV1
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
