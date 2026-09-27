"""Product-level Issue 4A plan evaluation orchestration.

The service keeps FastAPI stateless: one valid request produces one evaluation
result identity, while semantic equality/staleness is explained by versioned
basis fingerprints rather than server-side lifecycle state.
"""

from __future__ import annotations

import hmac
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from importlib.metadata import PackageNotFoundError, version as package_version
from uuid import UUID, uuid4

from pydantic import ValidationError

from apps.api.contracts import (
    ASSEMBLY_POLICY_VERSION,
    DOMAIN_SCHEMA_VERSION,
    RECONCILIATION_POLICY_VERSION,
    REPORT_WIRE_FINGERPRINT_VERSION,
    CandidateRefV1,
    CanonicalReportBundleV1,
    EvaluationBasisV1,
    PlanEvaluateRequestV1,
    PlanEvaluateResponseV1,
    PlanningBasisV1,
    PlanningDecisionV1,
    PublicCandidateV1,
    RecommendationSetV1,
    RecommendationTraceV1,
    RecommendationV1,
    ReadinessBasisV1,
    ReportBasisV1,
)
from apps.api.canonical_json import CanonicalJsonError, jcs_sha256
from apps.api.fingerprints import canonical_utc, report_wire_fingerprint
from engine.availability import build_availability
from engine.feasibility.service import (
    FeasibilityExecutionError,
    FeasibilityIndeterminateError,
    FeasibilityInputError,
    FeasibilityInvariantError,
    assess_feasibility_run,
)
from engine.integration.competition_analysis import (
    build_readiness_request,
    resolve_eligibility_scope,
)
from engine.recommendation import (
    RecommendationBuildInput,
    RecommendationEvidenceError,
    RecommendationInputError,
    RecommendationInvariantError,
    RecommendationTraceContext,
    build_recommendation,
)
from engine.scheduler import SolverConfig
from engine.triage.scope import ResolvedEligibilityScope
from engine.triage.service import evaluate_readiness
from packages.contracts import (
    AvailabilityInput,
    PlanningWorkWindow,
    ReadinessStatus,
    WorkloadInput,
)
from packages.contracts.triage import ReadinessRequest

Clock = Callable[[], datetime]
EvaluationIdFactory = Callable[[], UUID]


class ReportBundleError(ValueError):
    """The report bundle is not self-consistent at the public wire boundary."""


class UnsupportedReportContractError(ReportBundleError):
    """The client supplied a report contract version this API does not support."""


class PlanEvaluationInputError(ValueError):
    """Validated transport input is unusable by the decision pipeline."""


class PlanEvaluationIndeterminateError(RuntimeError):
    """The solver returned UNKNOWN on a material decision branch."""


class PlanEvaluationExecutionError(RuntimeError):
    """A planning engine could not execute correctly."""


class PlanEvaluationInvariantError(RuntimeError):
    """Server-produced artifacts contradict a frozen invariant."""


def _utc_now() -> datetime:
    return datetime.now(UTC)


def planning_cutoff(evaluated_at: datetime) -> datetime:
    """Return the first minute-aligned instant that is not before evaluated_at."""

    if evaluated_at.tzinfo is None or evaluated_at.utcoffset() is None:
        raise PlanEvaluationInvariantError("server clock must return an aware datetime")
    value = evaluated_at.astimezone(UTC)
    if value.second == 0 and value.microsecond == 0:
        return value
    return value.replace(second=0, microsecond=0) + timedelta(minutes=1)


def _valid_sha256(value: str) -> bool:
    if not isinstance(value, str) or len(value) != 64:
        return False
    try:
        int(value, 16)
    except ValueError:
        return False
    return value == value.lower()


def verify_report_bundle(bundle: CanonicalReportBundleV1) -> None:
    """Verify supported version metadata and JSON-wire self-consistency."""

    ref = bundle.ref
    supported = {
        "domain_schema_version": DOMAIN_SCHEMA_VERSION,
        "reconciliation_policy_version": RECONCILIATION_POLICY_VERSION,
        "assembly_policy_version": ASSEMBLY_POLICY_VERSION,
        "wire_fingerprint_version": REPORT_WIRE_FINGERPRINT_VERSION,
    }
    actual = {
        "domain_schema_version": ref.domain_schema_version,
        "reconciliation_policy_version": ref.reconciliation_policy_version,
        "assembly_policy_version": ref.assembly_policy_version,
        "wire_fingerprint_version": ref.wire_fingerprint_version,
    }
    if actual != supported:
        raise UnsupportedReportContractError(
            "report bundle uses an unsupported contract or policy version"
        )
    if ref.competition_id != bundle.report.competition_id:
        raise ReportBundleError("report ref competition_id does not match report")
    if ref.report_version != bundle.report.report_version:
        raise ReportBundleError("report ref report_version does not match report")
    if not _valid_sha256(ref.assembly_material_fingerprint):
        raise ReportBundleError("assembly material fingerprint is invalid")
    if not _valid_sha256(ref.wire_fingerprint):
        raise ReportBundleError("wire fingerprint is invalid")

    try:
        expected = report_wire_fingerprint(bundle.report, ref)
    except CanonicalJsonError as exc:
        raise ReportBundleError("report bundle cannot be canonicalized") from exc
    if not hmac.compare_digest(expected, bundle.ref.wire_fingerprint):
        raise ReportBundleError("report bundle wire fingerprint does not match payload")


def _canonical_scope_material(
    resolved: ResolvedEligibilityScope | None,
    selected_scope: str | None,
) -> dict[str, object]:
    if resolved is None:
        normalized = (
            selected_scope.strip().lower()
            if isinstance(selected_scope, str) and selected_scope.strip()
            else None
        )
        return {
            "state": "UNRESOLVED",
            "requested_scope": normalized,
        }

    if resolved.selected_scope.strip().lower() == "unscoped":
        return {"state": "UNSCOPED"}

    if resolved.canonical_dimension is None or resolved.canonical_value is None:
        raise PlanEvaluationInvariantError(
            "resolved scoped eligibility is missing canonical scope identity"
        )
    return {
        "state": "RESOLVED",
        "dimension": resolved.canonical_dimension,
        "value": resolved.canonical_value,
    }


def _normalized_regions(values: list[str]) -> tuple[str, ...]:
    normalized = {
        item.strip().lower()
        for item in values
        if isinstance(item, str) and item.strip()
    }
    if "global" in normalized:
        return ("global",)
    return tuple(sorted(normalized))


def _eligibility_predicates(request: ReadinessRequest) -> dict[str, object]:
    rules = request.eligibility
    user = request.user
    predicates: dict[str, object] = {}

    if rules.minimum_age is not None:
        if user.age is None:
            state = "UNKNOWN"
        elif user.age >= rules.minimum_age:
            state = "MET"
        else:
            state = "NOT_MET"
        predicates["minimum_age"] = {
            "required": rules.minimum_age,
            "state": state,
        }

    if rules.requires_student:
        if user.student_status is None:
            state = "UNKNOWN"
        elif user.student_status:
            state = "MET"
        else:
            state = "NOT_MET"
        predicates["student_status"] = {"state": state}

    regions = _normalized_regions(rules.allowed_regions)
    if regions and regions != ("global",):
        country = user.country.strip().lower() if user.country else None
        if country is None:
            state = "UNKNOWN"
        elif country in regions:
            state = "MET"
        else:
            state = "NOT_MET"
        predicates["region"] = {
            "allowed_regions": list(regions),
            "state": state,
        }

    return predicates


def _deadline_state(request: ReadinessRequest) -> str:
    if request.submission_deadline is None:
        return "UNAVAILABLE"
    if (
        request.submission_deadline <= request.evaluated_at
        and not request.has_applicable_deadline_extension
    ):
        return "PASSED"
    return "OPEN"


def _readiness_basis_fingerprint(
    request: ReadinessRequest,
    resolved_scope: ResolvedEligibilityScope | None,
    selected_scope: str | None,
) -> str:
    """Hash only readiness inputs actually consulted by triage-v1.

    The projection mirrors evaluate_readiness() short-circuit order so a field
    that cannot affect the current readiness result does not create stale/dedupe
    noise for Block 2.
    """

    material: dict[str, object] = {
        "projected_unresolved_fields": sorted(request.unresolved_critical_fields),
        "deadline": {"state": "NOT_EVALUATED"},
        "mandatory_information": {"state": "NOT_EVALUATED"},
        "eligibility": {"state": "NOT_EVALUATED"},
    }

    if request.unresolved_critical_fields:
        return jcs_sha256(material)

    deadline_state = _deadline_state(request)
    material["deadline"] = {
        "state": deadline_state,
        "deadline_extension_applicable": False,
    }
    if deadline_state != "OPEN":
        return jcs_sha256(material)

    mandatory_state = (
        "COMPLETE" if request.mandatory_information_complete else "INCOMPLETE"
    )
    material["mandatory_information"] = {"state": mandatory_state}
    if mandatory_state != "COMPLETE":
        return jcs_sha256(material)

    rules = request.eligibility
    user = request.user
    consulted: list[dict[str, object]] = []
    eligibility_material: dict[str, object] = {
        "state": "EVALUATING",
        "canonical_effective_scope": _canonical_scope_material(
            resolved_scope,
            selected_scope,
        ),
        "consulted_predicates": consulted,
    }

    if rules.minimum_age is not None:
        if user.age is None:
            state = "UNKNOWN"
        elif user.age >= rules.minimum_age:
            state = "MET"
        else:
            state = "NOT_MET"
        consulted.append(
            {
                "predicate": "minimum_age",
                "required": rules.minimum_age,
                "state": state,
            }
        )
        if state != "MET":
            material["eligibility"] = eligibility_material
            return jcs_sha256(material)

    if rules.requires_student:
        if user.student_status is None:
            state = "UNKNOWN"
        elif user.student_status:
            state = "MET"
        else:
            state = "NOT_MET"
        consulted.append(
            {
                "predicate": "student_status",
                "required": True,
                "state": state,
            }
        )
        if state != "MET":
            material["eligibility"] = eligibility_material
            return jcs_sha256(material)

    regions = _normalized_regions(rules.allowed_regions)
    if regions and regions != ("global",):
        country = user.country.strip().lower() if user.country else None
        if country is None:
            state = "UNKNOWN"
        elif country in regions:
            state = "MET"
        else:
            state = "NOT_MET"
        consulted.append(
            {
                "predicate": "region",
                "allowed_regions": list(regions),
                "state": state,
            }
        )
        if state != "MET":
            material["eligibility"] = eligibility_material
            return jcs_sha256(material)

    eligibility_material["state"] = "COMPLETE"
    material["eligibility"] = eligibility_material
    return jcs_sha256(material)


def _clip_planning_input(
    value: AvailabilityInput,
    cutoff: datetime,
) -> AvailabilityInput:
    try:
        clean = AvailabilityInput.model_validate(
            value.model_dump(mode="python", warnings=False)
        )
        windows: list[PlanningWorkWindow] = []
        for window in clean.work_windows:
            start = window.start.astimezone(UTC)
            end = window.end.astimezone(UTC)
            if end <= cutoff:
                continue
            windows.append(
                PlanningWorkWindow(
                    start=max(start, cutoff),
                    end=end,
                )
            )
        return AvailabilityInput(
            horizon=clean.horizon,
            work_windows=tuple(windows),
            commitments=clean.commitments,
            accepted_commitments=clean.accepted_commitments,
            preferences=clean.preferences,
        )
    except (TypeError, ValueError, ValidationError) as exc:
        raise PlanEvaluationInputError(
            "planning availability could not be projected at server cutoff"
        ) from exc


def _availability_material(availability) -> dict[str, object]:
    available = sorted(
        availability.available_blocks,
        key=lambda item: (
            item.start.astimezone(UTC),
            item.end.astimezone(UTC),
            item.source,
        ),
    )
    capacity = sorted(
        availability.daily_capacity,
        key=lambda item: item.local_date,
    )
    return {
        "timezone": availability.timezone,
        "horizon_start": canonical_utc(availability.horizon_start),
        "horizon_end": canonical_utc(availability.horizon_end),
        "available_blocks": [
            {
                "start": canonical_utc(item.start),
                "end": canonical_utc(item.end),
                "availability_source": item.source,
            }
            for item in available
        ],
        "daily_capacity": [
            {
                "local_date": item.local_date.isoformat(),
                "usable_project_minutes": item.usable_project_minutes,
            }
            for item in capacity
        ],
    }


def _workload_material(workload: WorkloadInput) -> dict[str, object]:
    tasks = sorted(workload.tasks, key=lambda item: item.task_id)
    assumptions = sorted(
        workload.assumptions,
        key=lambda item: (item.task_id or "", item.description),
    )
    return {
        "tasks": [
            {
                "task_id": item.task_id,
                "name": item.name,
                "mandatory": item.mandatory,
                "dependencies": sorted(item.dependencies),
                "effort_min_minutes": item.effort_min_minutes,
                "effort_likely_minutes": item.effort_likely_minutes,
                "effort_max_minutes": item.effort_max_minutes,
                "assumptions": sorted(item.assumptions),
            }
            for item in tasks
        ],
        "assumptions": [
            {
                "task_id": item.task_id,
                "description": item.description,
            }
            for item in assumptions
        ],
    }


def _solver_material(config: SolverConfig) -> dict[str, object]:
    return {
        "submission_deadline": canonical_utc(config.submission_deadline),
        "buffer_target_minutes": config.buffer_target_minutes,
        "effort_basis": config.effort_basis,
    }


def _solver_backend_version() -> str:
    try:
        return package_version("ortools")
    except PackageNotFoundError as exc:
        raise PlanEvaluationExecutionError(
            "OR-Tools package metadata is unavailable"
        ) from exc


def _report_basis(bundle: CanonicalReportBundleV1) -> ReportBasisV1:
    return ReportBasisV1(
        competition_id=bundle.ref.competition_id,
        report_version=bundle.ref.report_version,
        reconciliation_policy_version=bundle.ref.reconciliation_policy_version,
        assembly_policy_version=bundle.ref.assembly_policy_version,
        assembly_material_fingerprint=bundle.ref.assembly_material_fingerprint,
    )


def _evaluation_basis(
    *,
    report: ReportBasisV1,
    readiness: ReadinessBasisV1,
    planning: PlanningBasisV1 | None,
) -> EvaluationBasisV1:
    material = {
        "version": "evaluation-basis-v1",
        "domain_schema_version": "3.0.0",
        "report": report.model_dump(mode="json", warnings=False),
        "readiness": readiness.model_dump(mode="json", warnings=False),
        "planning": (
            planning.model_dump(mode="json", warnings=False)
            if planning is not None
            else None
        ),
    }
    return EvaluationBasisV1(
        fingerprint=jcs_sha256(material),
        report=report,
        readiness=readiness,
        planning=planning,
    )


def _new_evaluation_id(factory: EvaluationIdFactory) -> UUID:
    value = factory()
    if not isinstance(value, UUID) or value.version != 4:
        raise PlanEvaluationInvariantError(
            "evaluation ID factory must return a UUIDv4"
        )
    return value


def _assert_public_candidate_cutoff(feasibility_run, cutoff: datetime) -> None:
    for candidate in feasibility_run.likely_solver_result.candidate_allocations:
        for block in candidate.work_blocks:
            if block.start.astimezone(UTC) < cutoff:
                raise PlanEvaluationInvariantError(
                    "LIKELY candidate starts before server planning cutoff"
                )


def evaluate_plan(
    request: PlanEvaluateRequestV1,
    *,
    clock: Clock = _utc_now,
    evaluation_id_factory: EvaluationIdFactory = uuid4,
) -> PlanEvaluateResponseV1:
    """Run one stateless product evaluation over a validated report snapshot."""

    try:
        clean = PlanEvaluateRequestV1.model_validate(
            request.model_dump(mode="json", warnings=False)
        )
    except (AttributeError, TypeError, ValueError, ValidationError) as exc:
        raise PlanEvaluationInputError("invalid plan evaluation request") from exc

    verify_report_bundle(clean.report_bundle)

    evaluated_at = clock()
    if (
        not isinstance(evaluated_at, datetime)
        or evaluated_at.tzinfo is None
        or evaluated_at.utcoffset() is None
    ):
        raise PlanEvaluationInvariantError(
            "server clock must return a timezone-aware datetime"
        )
    evaluated_at = evaluated_at.astimezone(UTC)

    context = clean.readiness_context
    try:
        readiness_request = build_readiness_request(
            canonical_report=clean.report_bundle.report,
            user=context.user.to_domain(),
            selected_scope=context.selected_scope,
            evaluated_at=evaluated_at,
            require_technology_information=context.require_technology_information,
        )
        resolved_scope = resolve_eligibility_scope(
            canonical_report=clean.report_bundle.report,
            selected_scope=context.selected_scope,
        )
        readiness = evaluate_readiness(readiness_request)
    except (TypeError, ValueError, ValidationError) as exc:
        raise PlanEvaluationInputError(
            "report or readiness context could not be evaluated"
        ) from exc

    readiness_basis = ReadinessBasisV1(
        basis_fingerprint=_readiness_basis_fingerprint(
            readiness_request,
            resolved_scope,
            context.selected_scope,
        ),
        rule_version=readiness.rule_version,
    )
    report_basis = _report_basis(clean.report_bundle)

    if readiness.status is not ReadinessStatus.READY_TO_EVALUATE:
        basis = _evaluation_basis(
            report=report_basis,
            readiness=readiness_basis,
            planning=None,
        )
        evaluation_id = _new_evaluation_id(evaluation_id_factory)
        return PlanEvaluateResponseV1(
            evaluation_id=evaluation_id,
            evaluated_at=evaluated_at,
            basis=basis,
            readiness=readiness,
            planning=None,
        )

    if readiness_request.submission_deadline is None:
        raise PlanEvaluationInvariantError(
            "ready readiness result requires submission deadline"
        )

    cutoff = planning_cutoff(evaluated_at)
    availability_input = _clip_planning_input(
        clean.planning.availability,
        cutoff,
    )

    try:
        availability = build_availability(availability_input)
        config = SolverConfig(
            submission_deadline=readiness_request.submission_deadline,
            buffer_target_minutes=availability_input.preferences.buffer_target_minutes,
            effort_basis="LIKELY",
        )
    except (TypeError, ValueError, ValidationError) as exc:
        raise PlanEvaluationInputError(
            "planning input could not satisfy availability/solver contracts"
        ) from exc
    except RuntimeError as exc:
        raise PlanEvaluationExecutionError(
            "availability preparation failed"
        ) from exc

    planning_fingerprint = jcs_sha256(
        {
            "availability": _availability_material(availability),
            "workload": _workload_material(clean.planning.workload),
            "solver_config": _solver_material(config),
        }
    )
    planning_basis = PlanningBasisV1(
        basis_fingerprint=planning_fingerprint,
        solver_backend_version=_solver_backend_version(),
    )

    try:
        feasibility_run = assess_feasibility_run(
            availability,
            clean.planning.workload,
            config,
        )
    except FeasibilityInputError as exc:
        raise PlanEvaluationInputError(
            "planning input was rejected by feasibility analysis"
        ) from exc
    except FeasibilityIndeterminateError as exc:
        raise PlanEvaluationIndeterminateError(
            "solver result is indeterminate"
        ) from exc
    except FeasibilityExecutionError as exc:
        raise PlanEvaluationExecutionError(
            "solver execution failed"
        ) from exc
    except FeasibilityInvariantError as exc:
        raise PlanEvaluationInvariantError(
            "feasibility artifacts violate planning invariants"
        ) from exc

    _assert_public_candidate_cutoff(feasibility_run, cutoff)

    try:
        assembly = build_recommendation(
            RecommendationBuildInput(
                feasibility_run=feasibility_run,
                trace_context=RecommendationTraceContext.from_canonical_report(
                    clean.report_bundle.report
                ),
            )
        )
    except (
        RecommendationEvidenceError,
        RecommendationInputError,
        RecommendationInvariantError,
        ValidationError,
        ValueError,
    ) as exc:
        raise PlanEvaluationInvariantError(
            "recommendation assembly failed over server-produced artifacts"
        ) from exc

    if (
        assembly.source_competition_id != report_basis.competition_id
        or assembly.source_report_version != report_basis.report_version
    ):
        raise PlanEvaluationInvariantError(
            "recommendation trace does not match evaluation report basis"
        )

    basis = _evaluation_basis(
        report=report_basis,
        readiness=readiness_basis,
        planning=planning_basis,
    )
    evaluation_id = _new_evaluation_id(evaluation_id_factory)

    likely_candidates = feasibility_run.likely_solver_result.candidate_allocations
    candidate_by_id = {
        candidate.candidate_id: candidate
        for candidate in likely_candidates
        if candidate.is_recommendable
    }
    if len(candidate_by_id) != sum(
        1 for candidate in likely_candidates if candidate.is_recommendable
    ):
        raise PlanEvaluationInvariantError(
            "LIKELY public candidate pool contains duplicate candidate IDs"
        )

    recommendation_set = None
    public_candidates: tuple[PublicCandidateV1, ...] = ()
    if assembly.recommendation_payload is not None:
        try:
            recommendation = RecommendationV1.model_validate(
                assembly.recommendation_payload.model_dump(
                    mode="python",
                    warnings=False,
                )
            )
            if assembly.primary_candidate_id is None:
                raise PlanEvaluationInvariantError(
                    "recommendation payload is missing primary candidate identity"
                )

            public_candidate_ids = (
                assembly.primary_candidate_id,
                *assembly.alternative_candidate_ids,
            )
            if set(public_candidate_ids) != set(candidate_by_id):
                raise PlanEvaluationInvariantError(
                    "recommendation candidate IDs do not cover the valid LIKELY pool"
                )

            public_candidates = tuple(
                PublicCandidateV1(
                    ref=CandidateRefV1(
                        evaluation_id=evaluation_id,
                        candidate_id=candidate_id,
                    ),
                    work_blocks=candidate_by_id[candidate_id].work_blocks,
                    buffer_minutes=candidate_by_id[candidate_id].buffer_minutes,
                    assumptions=candidate_by_id[candidate_id].assumptions,
                )
                for candidate_id in public_candidate_ids
            )
            recommendation_set = RecommendationSetV1(
                primary_candidate=public_candidates[0].ref,
                alternative_candidates=tuple(
                    item.ref for item in public_candidates[1:]
                ),
                recommendation=recommendation,
                trace=RecommendationTraceV1(
                    competition_id=report_basis.competition_id,
                    report_version=report_basis.report_version,
                    assembly_material_fingerprint=(
                        report_basis.assembly_material_fingerprint
                    ),
                    evaluation_basis_fingerprint=basis.fingerprint,
                    planning_basis_fingerprint=planning_basis.basis_fingerprint,
                ),
            )
        except (KeyError, RecommendationInputError, ValidationError, ValueError) as exc:
            raise PlanEvaluationInvariantError(
                "public recommendation projection failed"
            ) from exc
    elif candidate_by_id:
        raise PlanEvaluationInvariantError(
            "non-recommendation assembly must not leave public LIKELY candidates"
        )

    assessment = feasibility_run.assessment
    planning = PlanningDecisionV1(
        feasibility=assessment.status,
        candidates=public_candidates,
        allowed_actions=assembly.allowed_actions,
        reason_codes=assessment.reason_codes,
        tradeoff_codes=assessment.tradeoff_codes,
        sensitivity_codes=assessment.sensitivity_codes,
        recommendation=recommendation_set,
    )
    return PlanEvaluateResponseV1(
        evaluation_id=evaluation_id,
        evaluated_at=evaluated_at,
        basis=basis,
        readiness=readiness,
        planning=planning,
    )
