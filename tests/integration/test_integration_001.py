from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

from engine.integration import build_readiness_request
from engine.triage.service import evaluate_readiness
from packages.contracts import ReadinessStatus, UserContext
from tests.integration.fixture_adapters import (
    canonical_report_from_preproduction_fixture,
)

FIXTURE_PATH = (
    Path(__file__).parent / "fixtures" / "integration_001_v2.json"
)


def _run_integration_001(fixture, canonical_report):
    policy = fixture["policy"]
    request = build_readiness_request(
        canonical_report=canonical_report,
        user=UserContext.model_validate(fixture["user"]),
        selected_scope=policy["eligibility_selected_scope"],
        evaluated_at=datetime.fromisoformat(fixture["evaluated_at"]),
        require_technology_information=policy["require_technology_information"],
    )
    return request, evaluate_readiness(request)


def test_integration_001_uses_versioned_current_triage_expectation() -> None:
    fixture = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))
    canonical_report = canonical_report_from_preproduction_fixture(fixture)
    expected = fixture["expected"]

    critical_provenance_before = {
        field_name: tuple(canonical_report.canonical_fields[field_name].evidence_ids)
        for field_name in ("submission_deadline", "eligibility")
    }
    assert all(critical_provenance_before.values())

    first_request, first_result = _run_integration_001(fixture, canonical_report)
    second_request, second_result = _run_integration_001(fixture, canonical_report)

    assert first_result.status is ReadinessStatus(expected["status"])
    assert first_result.blocking_reasons == expected["blocking_reasons"]
    assert first_result.review_items == expected["review_items"]
    assert first_result.passed_checks == expected["passed_checks"]
    assert first_result.rule_version == expected["rule_version"]
    assert first_request.has_applicable_deadline_extension is False

    critical_provenance_after = {
        field_name: tuple(canonical_report.canonical_fields[field_name].evidence_ids)
        for field_name in ("submission_deadline", "eligibility")
    }
    assert critical_provenance_after == critical_provenance_before

    serialized = json.dumps(first_result.model_dump(mode="json"), sort_keys=True)
    assert "JOIN" not in serialized
    assert "DO_NOT_JOIN" not in serialized

    planning_gate_open = (
        first_result.status is ReadinessStatus.READY_TO_EVALUATE
    )
    assert planning_gate_open is True

    assert second_request.model_dump(mode="json") == first_request.model_dump(
        mode="json"
    )
    assert second_result.model_dump(mode="json") == first_result.model_dump(
        mode="json"
    )
