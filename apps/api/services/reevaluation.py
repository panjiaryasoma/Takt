"""Deterministic re-evaluation state machine for Issue 4A Block 2."""

from __future__ import annotations

import hmac
from dataclasses import dataclass
from datetime import UTC, datetime
from uuid import uuid4

from apps.api.canonical_json import jcs_sha256
from apps.api.contracts import (
    PLANNING_BASIS_VERSION,
    PLANNING_POLICY_VERSION,
    READINESS_BASIS_VERSION,
    READINESS_PROJECTION_VERSION,
    SOLVER_BACKEND,
    EvaluationBasisV1,
    PlanReevaluateRequestV1,
    PlanReevaluateResponseV1,
    PriorEvaluationBasisSnapshotV1,
    ReevaluationChangeReasonV1,
    ReevaluationTransitionV1,
)
from apps.api.services.plan_evaluation import (
    Clock,
    EvaluationIdFactory,
    PlanEvaluationInvariantError,
    PreparedEvaluation,
    ReadinessExecution,
    execute_prepared_evaluation,
    execute_readiness_stage,
    finalize_evaluation_basis,
    finalize_planning_stage,
    prepare_planning_material_stage,
    prepare_readiness_basis_stage,
    prepare_report_stage,
    sample_server_clock,
)
from engine.triage.service import READINESS_RULE_VERSION
from packages.contracts import ReadinessStatus


class ReevaluationContextInvalid(ValueError):
    """Trusted comparison context is internally inconsistent."""


class ReevaluationExecutionFailure(Exception):
    """Carry a downstream failure together with already-proven freshness."""

    def __init__(
        self,
        *,
        cause: Exception,
        transition: ReevaluationTransitionV1 | None,
    ) -> None:
        super().__init__(str(cause))
        self.cause = cause
        self.transition = transition


def _utc_now() -> datetime:
    return datetime.now(UTC)


@dataclass(slots=True)
class StaleWitness:
    reasons: list[ReevaluationChangeReasonV1]

    def add(self, reason: ReevaluationChangeReasonV1) -> None:
        if reason not in self.reasons:
            self.reasons.append(reason)

    @property
    def established(self) -> bool:
        return bool(self.reasons)

    def transition(
        self,
        request: PlanReevaluateRequestV1,
        *,
        current_basis_fingerprint: str | None,
    ) -> ReevaluationTransitionV1 | None:
        if not self.established:
            return None
        return ReevaluationTransitionV1(
            kind="SUPERSEDED",
            prior_evaluation_id=request.prior.evaluation_id,
            prior_basis_fingerprint=request.prior.basis.fingerprint,
            current_basis_fingerprint=current_basis_fingerprint,
            prior_evaluation_freshness="STALE",
            change_reasons=tuple(self.reasons),
        )


def _basis_material(
    basis: PriorEvaluationBasisSnapshotV1,
) -> dict[str, object]:
    return {
        "version": basis.version,
        "domain_schema_version": basis.domain_schema_version,
        "report": basis.report.model_dump(mode="json", warnings=False),
        "readiness": basis.readiness.model_dump(mode="json", warnings=False),
        "planning": (
            basis.planning.model_dump(mode="json", warnings=False)
            if basis.planning is not None
            else None
        ),
    }


def _verify_prior_fingerprint(basis: PriorEvaluationBasisSnapshotV1) -> None:
    expected = jcs_sha256(_basis_material(basis))
    if not hmac.compare_digest(expected, basis.fingerprint):
        raise ReevaluationContextInvalid(
            "prior evaluation basis fingerprint does not match its material"
        )


def _report_material(value) -> dict[str, object]:
    return {
        "competition_id": value.competition_id,
        "report_version": value.report_version,
        "reconciliation_policy_version": value.reconciliation_policy_version,
        "assembly_policy_version": value.assembly_policy_version,
        "assembly_material_fingerprint": value.assembly_material_fingerprint,
    }


def _readiness_material(value) -> dict[str, object]:
    return {
        "basis_version": value.basis_version,
        "basis_fingerprint": value.basis_fingerprint,
        "projection_version": value.projection_version,
        "rule_version": value.rule_version,
    }


def _planning_material(value) -> dict[str, object]:
    return {
        "basis_version": value.basis_version,
        "basis_fingerprint": value.basis_fingerprint,
        "policy_version": value.policy_version,
        "solver_backend": value.solver_backend,
        "solver_backend_version": value.solver_backend_version,
    }


def _verify_report_lineage(
    request: PlanReevaluateRequestV1,
    current_report,
) -> None:
    prior = request.prior.basis.report
    if prior.competition_id != current_report.competition_id:
        raise ReevaluationContextInvalid(
            "re-evaluation must stay within one competition lineage"
        )
    if current_report.report_version < prior.report_version:
        raise ReevaluationContextInvalid(
            "current report version cannot regress below prior report version"
        )
    if (
        current_report.report_version == prior.report_version
        and current_report.assembly_material_fingerprint
        != prior.assembly_material_fingerprint
    ):
        raise ReevaluationContextInvalid(
            "same report version cannot carry different canonical material"
        )


def _compare_report(
    request: PlanReevaluateRequestV1,
    current,
    witness: StaleWitness,
) -> None:
    if _report_material(request.prior.basis.report) != _report_material(current):
        witness.add("REPORT_BASIS_CHANGED")


def _compare_static_readiness(
    request: PlanReevaluateRequestV1,
    witness: StaleWitness,
) -> None:
    prior = request.prior.basis.readiness
    current_static = {
        "basis_version": READINESS_BASIS_VERSION,
        "projection_version": READINESS_PROJECTION_VERSION,
        "rule_version": READINESS_RULE_VERSION,
    }
    prior_static = {
        "basis_version": prior.basis_version,
        "projection_version": prior.projection_version,
        "rule_version": prior.rule_version,
    }
    if prior_static != current_static:
        witness.add("READINESS_BASIS_CHANGED")


def _compare_readiness(
    request: PlanReevaluateRequestV1,
    current,
    witness: StaleWitness,
) -> bool:
    same = _readiness_material(request.prior.basis.readiness) == _readiness_material(
        current
    )
    if not same:
        witness.add("READINESS_BASIS_CHANGED")
    return same


def _validate_planning_presence(
    request: PlanReevaluateRequestV1,
    *,
    current_ready: bool,
    readiness_same: bool,
) -> None:
    if not readiness_same:
        return
    prior_has_planning = request.prior.basis.planning is not None
    if prior_has_planning != current_ready:
        raise ReevaluationContextInvalid(
            "equal readiness basis cannot change planning-stage presence"
        )


def _compare_static_planning(
    request: PlanReevaluateRequestV1,
    witness: StaleWitness,
) -> None:
    prior = request.prior.basis.planning
    if prior is None:
        return
    prior_static = {
        "basis_version": prior.basis_version,
        "policy_version": prior.policy_version,
        "solver_backend": prior.solver_backend,
    }
    current_static = {
        "basis_version": PLANNING_BASIS_VERSION,
        "policy_version": PLANNING_POLICY_VERSION,
        "solver_backend": SOLVER_BACKEND,
    }
    if prior_static != current_static:
        witness.add("PLANNING_BASIS_CHANGED")


def _compare_planning_fingerprint(
    request: PlanReevaluateRequestV1,
    current_fingerprint: str,
    witness: StaleWitness,
) -> None:
    prior = request.prior.basis.planning
    if prior is not None and prior.basis_fingerprint != current_fingerprint:
        witness.add("PLANNING_BASIS_CHANGED")


def _compare_full_planning(
    request: PlanReevaluateRequestV1,
    current,
    witness: StaleWitness,
) -> None:
    prior = request.prior.basis.planning
    if prior is not None and _planning_material(prior) != _planning_material(current):
        witness.add("PLANNING_BASIS_CHANGED")


def _final_transition(
    request: PlanReevaluateRequestV1,
    current_basis: EvaluationBasisV1,
    witness: StaleWitness,
) -> ReevaluationTransitionV1:
    changed = current_basis.fingerprint != request.prior.basis.fingerprint
    if changed != witness.established:
        raise PlanEvaluationInvariantError(
            "evaluation fingerprint and component change reasons disagree"
        )
    if not changed:
        return ReevaluationTransitionV1(
            kind="UNCHANGED",
            prior_evaluation_id=request.prior.evaluation_id,
            prior_basis_fingerprint=request.prior.basis.fingerprint,
            current_basis_fingerprint=current_basis.fingerprint,
            prior_evaluation_freshness="CURRENT",
            change_reasons=(),
        )
    transition = witness.transition(
        request,
        current_basis_fingerprint=current_basis.fingerprint,
    )
    if transition is None:
        raise PlanEvaluationInvariantError(
            "changed evaluation basis requires stale witness"
        )
    return transition


def _execute_success(
    request: PlanReevaluateRequestV1,
    prepared: PreparedEvaluation,
    transition: ReevaluationTransitionV1,
    *,
    evaluation_id_factory: EvaluationIdFactory,
) -> PlanReevaluateResponseV1:
    evaluation = execute_prepared_evaluation(
        prepared,
        evaluation_id_factory=evaluation_id_factory,
    )
    return PlanReevaluateResponseV1(
        transition=transition,
        evaluation=evaluation,
    )


def reevaluate_plan(
    request: PlanReevaluateRequestV1,
    *,
    clock: Clock = _utc_now,
    evaluation_id_factory: EvaluationIdFactory = uuid4,
) -> PlanReevaluateResponseV1:
    """Compare semantic state first; execute only when the prior state is stale."""

    witness = StaleWitness(reasons=[])
    trusted_transition: ReevaluationTransitionV1 | None = None

    try:
        _verify_prior_fingerprint(request.prior.basis)

        report = prepare_report_stage(request.current)
        _verify_report_lineage(request, report.report_basis)
        _compare_report(request, report.report_basis, witness)
        trusted_transition = witness.transition(
            request,
            current_basis_fingerprint=None,
        )

        _compare_static_readiness(request, witness)
        trusted_transition = witness.transition(
            request,
            current_basis_fingerprint=None,
        )

        evaluated_at = sample_server_clock(clock)
        readiness_preparation = prepare_readiness_basis_stage(report, evaluated_at)
        readiness_same = _compare_readiness(
            request,
            readiness_preparation.readiness_basis,
            witness,
        )
        trusted_transition = witness.transition(
            request,
            current_basis_fingerprint=None,
        )

        readiness = execute_readiness_stage(readiness_preparation)
        current_ready = (
            readiness.readiness.status is ReadinessStatus.READY_TO_EVALUATE
        )
        _validate_planning_presence(
            request,
            current_ready=current_ready,
            readiness_same=readiness_same,
        )

        if not current_ready:
            prepared = finalize_evaluation_basis(readiness, None)
            transition = _final_transition(request, prepared.basis, witness)
            if transition.kind == "UNCHANGED":
                return PlanReevaluateResponseV1(
                    transition=transition,
                    evaluation=None,
                )
            return _execute_success(
                request,
                prepared,
                transition,
                evaluation_id_factory=evaluation_id_factory,
            )

        _compare_static_planning(request, witness)
        trusted_transition = witness.transition(
            request,
            current_basis_fingerprint=None,
        )

        planning_material = prepare_planning_material_stage(readiness)
        _compare_planning_fingerprint(
            request,
            planning_material.basis_fingerprint,
            witness,
        )
        trusted_transition = witness.transition(
            request,
            current_basis_fingerprint=None,
        )

        planning = finalize_planning_stage(planning_material)
        _compare_full_planning(
            request,
            planning.planning_basis,
            witness,
        )
        trusted_transition = witness.transition(
            request,
            current_basis_fingerprint=None,
        )

        prepared = finalize_evaluation_basis(readiness, planning)
        transition = _final_transition(request, prepared.basis, witness)
        if transition.kind == "UNCHANGED":
            return PlanReevaluateResponseV1(
                transition=transition,
                evaluation=None,
            )
        return _execute_success(
            request,
            prepared,
            transition,
            evaluation_id_factory=evaluation_id_factory,
        )

    except ReevaluationContextInvalid:
        raise
    except ReevaluationExecutionFailure:
        raise
    except PlanEvaluationInvariantError as exc:
        # A comparison/fingerprint contradiction is not trustworthy stale evidence.
        if "fingerprint and component change reasons disagree" in str(exc):
            raise ReevaluationExecutionFailure(
                cause=exc,
                transition=None,
            ) from exc
        raise ReevaluationExecutionFailure(
            cause=exc,
            transition=trusted_transition,
        ) from exc
    except Exception as exc:
        raise ReevaluationExecutionFailure(
            cause=exc,
            transition=trusted_transition,
        ) from exc
