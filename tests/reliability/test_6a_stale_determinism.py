"""Trust, semantic determinism and references survive hostile boundary states."""

from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient

import apps.api.routes.plans as route
import apps.api.services.plan_evaluation as evaluation
from apps.api.main import app
from apps.api.services.competition_analysis import analyze_pdf
from apps.api.services.reevaluation import reevaluate_plan
from engine.scheduler.invariants import candidate_hard_constraint_violations
from engine.workload import analyze_workload
from packages.contracts import CandidateAllocation, CanonicalFieldState, WorkloadInput
from tests.api.test_competition_analysis_behavior import _pdf_bytes, _StaticOCRProvider
from tests.api.test_plan_evaluate_behavior import _bundle, _id_one, _id_two, _prior_request
from tests.reliability.support import (
    PLAN_ENDPOINT,
    PRIVATE_SENTINEL,
    REEVALUATE_ENDPOINT,
    assert_public_failure,
    clock,
    domain_request,
    pdf_metadata,
    plan_request,
)
from tests.support.recovery_policy import recovery_for
from tests.support.semantic_projection import semantic_projection


def _candidate_request(kind):
    request = plan_request(effort_minutes=30)
    if kind == "dependencies":
        first = request.planning.workload.tasks[0]
        second = first.model_copy(update={"task_id": "task-2", "dependencies": (first.task_id,)})
        request = request.model_copy(
            update={
                "planning": request.planning.model_copy(
                    update={
                        "workload": WorkloadInput(tasks=(first, second)),
                    }
                )
            }
        )
    elif kind == "tight":
        request = domain_request("NARROW_CAPACITY")
    return request


@pytest.mark.parametrize("kind", ["ready", "dependencies", "tight"])
def test_same_semantics_and_every_candidate_reference_and_hard_constraint(kind):
    request = _candidate_request(kind)
    first = evaluation.evaluate_plan(request, clock=clock, evaluation_id_factory=_id_one)
    # A round trip and object-key reordering preserve semantic input.
    payload = request.model_dump(mode="json")
    second_request = type(request).model_validate(dict(reversed(list(payload.items()))))
    second = evaluation.evaluate_plan(second_request, clock=clock, evaluation_id_factory=_id_two)
    assert first.evaluation_id != second.evaluation_id
    assert semantic_projection(first) == semantic_projection(second)
    material = evaluation.prepare_evaluation(request, clock=clock).planning.material
    workload = analyze_workload(request.planning.workload)
    tasks = {task.task_id: task for task in workload.tasks}
    assert len(tasks) == len(workload.tasks)
    candidates = {item.ref.candidate_id: item for item in first.planning.candidates}
    assert candidates and len(candidates) == len(first.planning.candidates)
    recommendation = first.planning.recommendation
    refs = (recommendation.primary_candidate, *recommendation.alternative_candidates)
    assert [ref.candidate_id for ref in refs] == list(candidates)
    for ref in refs:
        assert ref.evaluation_id == first.evaluation_id
        candidate = candidates[ref.candidate_id]
        internal = CandidateAllocation(
            candidate_id=ref.candidate_id,
            work_blocks=candidate.work_blocks,
            buffer_minutes=candidate.buffer_minutes,
            assumptions=candidate.assumptions,
            hard_constraint_violations=(),
        )
        assert (
            candidate_hard_constraint_violations(
                internal,
                material.availability,
                workload,
                material.solver_config,
            )
            == ()
        )
        for block in candidate.work_blocks:
            assert block.task_id in tasks
            assert any(
                window.source == block.availability_source
                and window.start <= block.start < block.end <= window.end
                for window in material.availability.available_blocks
            )
    trace = recommendation.trace
    assert trace.evaluation_basis_fingerprint == first.basis.fingerprint
    assert trace.planning_basis_fingerprint == first.basis.planning.basis_fingerprint
    assert trace.report_version == first.basis.report.report_version
    assert trace.assembly_material_fingerprint == first.basis.report.assembly_material_fingerprint


def _changed_request(kind):
    request = plan_request(effort_minutes=60)
    if kind == "report":
        report = request.report_bundle.report
        return request.model_copy(
            update={
                "report_bundle": _bundle(
                    report.model_copy(
                        update={
                            "report_version": report.report_version + 1,
                        }
                    )
                )
            }
        )
    return plan_request(effort_minutes=61)


@pytest.mark.parametrize(
    "kind,reason",
    [
        ("report", "REPORT_BASIS_CHANGED"),
        ("planning", "PLANNING_BASIS_CHANGED"),
    ],
)
def test_material_basis_change_supersedes_deterministically(kind, reason):
    request, prior = _prior_request(current=_changed_request(kind))
    first = reevaluate_plan(request, clock=clock, evaluation_id_factory=_id_two)
    second = reevaluate_plan(request, clock=clock)
    assert semantic_projection(first) == semantic_projection(second)
    transition = first.transition
    assert transition.kind == "SUPERSEDED"
    assert transition.prior_evaluation_freshness == "STALE"
    assert transition.change_reasons == (reason,)
    assert transition.prior_evaluation_id == prior.evaluation_id
    assert transition.prior_basis_fingerprint == prior.basis.fingerprint
    assert transition.current_basis_fingerprint == first.evaluation.basis.fingerprint
    assert first.evaluation.evaluation_id != prior.evaluation_id
    assert recovery_for("STALE_SUPERSEDED") == "REEVALUATE"


@pytest.mark.parametrize("report_changed", [False, True])
def test_availability_failure_preserves_only_an_already_trusted_witness(
    monkeypatch, report_changed
):
    current = _changed_request("report") if report_changed else plan_request(effort_minutes=60)
    request, prior = _prior_request(current=current)
    monkeypatch.setattr(
        evaluation, "build_availability", Mock(side_effect=RuntimeError(PRIVATE_SENTINEL))
    )
    monkeypatch.setattr(route, "reevaluate_plan", lambda value: reevaluate_plan(value, clock=clock))
    with TestClient(app) as client:
        response = client.post(REEVALUATE_ENDPOINT.split()[1], json=request.model_dump(mode="json"))
    expected = None
    if report_changed:
        expected = {
            "kind": "SUPERSEDED",
            "prior_evaluation_id": str(prior.evaluation_id),
            "prior_basis_fingerprint": prior.basis.fingerprint,
            "current_basis_fingerprint": None,
            "prior_evaluation_freshness": "STALE",
            "change_reasons": ["REPORT_BASIS_CHANGED"],
        }
    assert_public_failure(
        response,
        REEVALUATE_ENDPOINT,
        "ReevaluationExecutionFailure[PlanEvaluationAvailabilityError]",
        transition=expected,
    )


def test_corrupt_prior_fingerprint_never_fabricates_stale_or_runs_solver(monkeypatch):
    request, _ = _prior_request(current=_changed_request("report"))
    payload = request.model_dump(mode="json")
    payload["prior"]["basis"]["fingerprint"] = "0" * 64
    solve = Mock(side_effect=AssertionError("Untrusted context must not execute"))
    monkeypatch.setattr(evaluation, "assess_feasibility_run", solve)
    monkeypatch.setattr(route, "reevaluate_plan", lambda value: reevaluate_plan(value, clock=clock))
    with TestClient(app) as client:
        response = client.post(REEVALUATE_ENDPOINT.split()[1], json=payload)
    assert_public_failure(response, REEVALUATE_ENDPOINT, "ReevaluationContextInvalid")
    solve.assert_not_called()


@pytest.mark.parametrize(
    "scenario",
    [
        "ready",
        "DEADLINE_PASSED",
        "FAILED_ELIGIBILITY",
        "UNKNOWN_USER_ATTRIBUTE",
        "CRITICAL_CONFLICT",
        "SOLVER_INFEASIBLE",
        "NARROW_CAPACITY",
    ],
)
def test_entitlement_headers_cannot_change_domain_or_recommendation_correctness(
    monkeypatch, scenario
):
    request = plan_request(effort_minutes=60) if scenario == "ready" else domain_request(scenario)
    before = request.report_bundle.model_dump(mode="json")
    monkeypatch.setattr(
        route, "evaluate_plan", lambda value: evaluation.evaluate_plan(value, clock=clock)
    )
    outputs = []
    with TestClient(app) as client:
        for headers in (
            {},
            {"X-RevenueCat-Entitlement": "free"},
            {"X-RevenueCat-Entitlement": "pro", "X-Subscription-Tier": "premium"},
        ):
            response = client.post(
                PLAN_ENDPOINT.split()[1], json=request.model_dump(mode="json"), headers=headers
            )
            assert response.status_code == 200, response.text
            outputs.append(semantic_projection(response.json()))
    assert outputs[0] == outputs[1] == outputs[2]
    assert request.report_bundle.model_dump(mode="json") == before


def test_native_ocr_disagreement_stays_conflict_with_resolvable_evidence():
    result = analyze_pdf(
        pdf_metadata(),
        _pdf_bytes("Submission deadline: September 30 2026 at 23:59 WIB"),
        ocr_provider=_StaticOCRProvider("Submission deadline: October 1 2026 at 23:59 WIB"),
    )
    deadline = result.report_bundle.report.canonical_fields["submission_deadline"]
    assert deadline.state is CanonicalFieldState.CONFLICT
    assert deadline.value is None and deadline.normalized_value is None
    assert len(deadline.candidates) == 2
    evidence_ids = {span.evidence_id for span in result.provenance.evidence}
    assert all(set(candidate.evidence_ids) <= evidence_ids for candidate in deadline.candidates)
    request = plan_request(effort_minutes=60).model_copy(
        update={"report_bundle": result.report_bundle}
    )
    evaluated = evaluation.evaluate_plan(request, clock=clock)
    assert evaluated.readiness.status.value == "NEEDS_REVIEW"
    assert evaluated.planning is None and evaluated.basis.planning is None
