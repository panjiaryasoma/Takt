"""Count owned transactions and intentional solve stages, not elapsed time."""

from unittest.mock import Mock

import httpx
import pytest

import apps.api.services.competition_analysis as analysis
import apps.api.services.plan_evaluation as evaluation
import engine.extraction.snapshot_pipeline as pipeline
import engine.feasibility.service as feasibility
import engine.scheduler.service as scheduler
from apps.api.services import reevaluation
from engine.feasibility.scenarios import SCENARIO_ORDER
from tests.api.test_plan_evaluate_behavior import _prior_request
from tests.reliability.support import (
    EmptyOCR,
    clock,
    domain_request,
    pdf_bytes,
    plan_request,
    public_dns,
    url_request,
)
from tests.support.recovery_policy import recovery_for


def test_url_pdf_redirect_is_one_retrieval_and_one_snapshot_fanned_out(monkeypatch):
    monkeypatch.setattr("engine.extraction.url_security.socket.getaddrinfo", public_dns)
    content = pdf_bytes()
    requests = []
    fetched = []
    real_fetch = analysis.fetch_url_snapshot

    def fetch(*args, **kwargs):
        snapshot = real_fetch(*args, **kwargs)
        fetched.append(snapshot)
        return snapshot

    def respond(request):
        requests.append(str(request.url))
        if request.url.path == "/rules":
            return httpx.Response(302, headers={"location": "/rules.pdf"}, request=request)
        return httpx.Response(
            200, content=content, headers={"content-type": "application/pdf"}, request=request
        )

    native = Mock(wraps=pipeline.extract_native_snapshot)
    ocr = Mock(side_effect=lambda snapshot, **_kwargs: real_ocr(snapshot, provider=EmptyOCR()))
    real_ocr = pipeline.extract_ocr_snapshot
    monkeypatch.setattr(analysis, "fetch_url_snapshot", fetch)
    monkeypatch.setattr(pipeline, "extract_native_snapshot", native)
    monkeypatch.setattr(pipeline, "extract_ocr_snapshot", ocr)
    with httpx.Client(transport=httpx.MockTransport(respond)) as client:
        result = analysis.analyze_url(url_request(), client=client)
    assert requests == ["https://example.test/rules", "https://example.test/rules.pdf"]
    assert len(fetched) == 1
    native.assert_called_once()
    ocr.assert_called_once()
    assert native.call_args.args[0] is fetched[0]
    assert ocr.call_args.args[0] is fetched[0]
    assert fetched[0].content == content
    assert len(result.provenance.extraction_runs) == 2


@pytest.mark.parametrize("blocked", [False, True])
def test_unchanged_has_no_new_execution_id_or_solver_material(monkeypatch, blocked):
    base = domain_request("CRITICAL_CONFLICT") if blocked else plan_request(effort_minutes=60)
    request, prior = _prior_request(prior=base)
    availability = Mock(wraps=evaluation.build_availability)
    execute = Mock(side_effect=AssertionError("UNCHANGED must not execute a fresh evaluation"))
    solve = Mock(side_effect=AssertionError("UNCHANGED must not solve"))
    uuid = Mock(side_effect=AssertionError("UNCHANGED must not allocate an ID"))
    monkeypatch.setattr(evaluation, "build_availability", availability)
    monkeypatch.setattr(reevaluation, "execute_prepared_evaluation", execute)
    monkeypatch.setattr(evaluation, "assess_feasibility_run", solve)
    first = reevaluation.reevaluate_plan(request, clock=clock, evaluation_id_factory=uuid)
    assert first.transition.kind == "UNCHANGED"
    assert first.transition.prior_evaluation_freshness == "CURRENT"
    assert first.transition.current_basis_fingerprint == prior.basis.fingerprint
    assert first.transition.change_reasons == ()
    assert first.evaluation is None
    assert availability.call_count == (0 if blocked else 1)
    execute.assert_not_called()
    solve.assert_not_called()
    uuid.assert_not_called()
    assert recovery_for("BASIS_UNCHANGED") == "NO_AUTOMATIC_RECOVERY"


def test_one_evaluation_solves_each_scenario_once_and_reuses_likely_artifacts(monkeypatch):
    availability = Mock(wraps=evaluation.build_availability)
    assess = Mock(wraps=evaluation.assess_feasibility_run)
    real_solve = feasibility.solve_candidate_allocations
    real_cp = scheduler.solve_cp_sat
    scenario_runs = []
    candidate_searches = []

    def solve(*args):
        searches = []
        candidate_searches.append(searches)
        result = real_solve(*args)
        scenario_runs.append(result)
        return result

    def cp(*args, **kwargs):
        prior = kwargs["materially_distinct_from"]
        candidate_searches[-1].append(len(prior))
        return real_cp(*args, **kwargs)

    monkeypatch.setattr(evaluation, "build_availability", availability)
    monkeypatch.setattr(evaluation, "assess_feasibility_run", assess)
    monkeypatch.setattr(feasibility, "solve_candidate_allocations", solve)
    monkeypatch.setattr(scheduler, "solve_cp_sat", cp)
    result = evaluation.evaluate_plan(plan_request(effort_minutes=60), clock=clock)
    availability.assert_called_once()
    assess.assert_called_once()
    assert len(scenario_runs) == len(SCENARIO_ORDER) == 4
    for search in candidate_searches:
        assert 1 <= len(search) <= 3
        assert search == list(range(len(search)))
    likely_index = [scenario.value for scenario in SCENARIO_ORDER].index("LIKELY")
    likely = scenario_runs[likely_index].candidate_allocations
    assert [
        (candidate.ref.candidate_id, candidate.work_blocks, candidate.buffer_minutes)
        for candidate in result.planning.candidates
    ] == [
        (candidate.candidate_id, candidate.work_blocks, candidate.buffer_minutes)
        for candidate in likely
    ]
