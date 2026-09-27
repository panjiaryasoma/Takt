"""Issue 4A contract tests for the product evaluation boundary."""

from __future__ import annotations

import json
from datetime import UTC, datetime, timedelta
from uuid import UUID

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from apps.api.contracts import (
    CanonicalReportBundleV1,
    CanonicalReportRefV1,
    PlanEvaluatePlanningV1,
    PlanEvaluateRequestV1,
    ReadinessContextV1,
    ReadinessUserContextV1,
)
from apps.api.canonical_json import CanonicalJsonError, jcs_dumps
from apps.api.fingerprints import report_wire_fingerprint
from apps.api.main import app
from engine.integration.plan_evaluation import (
    ReportBundleError,
    UnsupportedReportContractError,
    evaluate_plan,
    verify_report_bundle,
)
from packages.contracts import (
    AvailabilityInput,
    CanonicalCompetitionReport,
    CanonicalField,
    CanonicalFieldState,
    PlanningHorizon,
    PlanningPreferences,
    PlanningWorkWindow,
    ReadinessStatus,
    WorkloadInput,
)
from packages.contracts.source import CORE_CANONICAL_FIELDS


def _report() -> CanonicalCompetitionReport:
    fields = {
        name: CanonicalField(
            field_name=name,
            state=CanonicalFieldState.MISSING,
        )
        for name in CORE_CANONICAL_FIELDS
    }
    return CanonicalCompetitionReport(
        competition_id="cmp-001",
        report_version=3,
        source_ids=["src-001"],
        canonical_fields=fields,
        unresolved_critical_fields=["eligibility", "submission_deadline"],
    )


def _bundle() -> CanonicalReportBundleV1:
    report = _report()
    initial = CanonicalReportRefV1(
        competition_id=report.competition_id,
        report_version=report.report_version,
        assembly_material_fingerprint="a" * 64,
        wire_fingerprint="0" * 64,
    )
    ref = initial.model_copy(
        update={"wire_fingerprint": report_wire_fingerprint(report, initial)}
    )
    return CanonicalReportBundleV1(report=report, ref=ref)


def _planning() -> PlanEvaluatePlanningV1:
    start = datetime(2026, 9, 28, 8, 0, tzinfo=UTC)
    end = start + timedelta(hours=8)
    return PlanEvaluatePlanningV1(
        workload=WorkloadInput(tasks=()),
        availability=AvailabilityInput(
            horizon=PlanningHorizon(start=start, end=end),
            work_windows=(PlanningWorkWindow(start=start, end=end),),
            preferences=PlanningPreferences(
                timezone="UTC",
                max_project_minutes_per_day=480,
                preferred_focus_minutes=60,
                buffer_target_minutes=30,
            ),
        ),
    )


def _request() -> PlanEvaluateRequestV1:
    return PlanEvaluateRequestV1(
        report_bundle=_bundle(),
        readiness_context=ReadinessContextV1(
            user=ReadinessUserContextV1(),
            selected_scope=None,
            require_technology_information=False,
        ),
        planning=_planning(),
    )


def test_product_request_rejects_client_evaluated_at() -> None:
    payload = _request().model_dump(mode="json")
    payload["readiness_context"]["evaluated_at"] = "2026-09-27T00:00:00Z"

    with pytest.raises(ValidationError):
        PlanEvaluateRequestV1.model_validate(payload)


def test_blocked_readiness_does_not_execute_or_emit_planning_basis() -> None:
    fixed_clock = lambda: datetime(2026, 9, 27, 6, 30, tzinfo=UTC)
    fixed_id = lambda: UUID("123e4567-e89b-42d3-a456-426614174000")

    result = evaluate_plan(
        _request(),
        clock=fixed_clock,
        evaluation_id_factory=fixed_id,
    )

    assert result.readiness.status is ReadinessStatus.INSUFFICIENT_INFORMATION
    assert result.planning is None
    assert result.basis.planning is None
    assert result.evaluated_at == fixed_clock()


def test_wire_fingerprint_survives_json_round_trip() -> None:
    bundle = _bundle()
    raw = json.loads(json.dumps(bundle.model_dump(mode="json")))
    round_tripped = CanonicalReportBundleV1.model_validate(raw)

    verify_report_bundle(round_tripped)
    assert round_tripped.ref.wire_fingerprint == bundle.ref.wire_fingerprint


def test_jcs_normalizes_object_order_and_equivalent_number_shape() -> None:
    left = {"b": 1.0, "a": [1e-6, 1e21]}
    right = {"a": [0.000001, 1e21], "b": 1}

    assert jcs_dumps(left) == jcs_dumps(right)


def test_api_validation_error_uses_stable_envelope_and_json_pointer() -> None:
    payload = _request().model_dump(mode="json")
    payload["readiness_context"]["evaluated_at"] = "2026-09-27T00:00:00Z"

    response = TestClient(app).post("/api/v1/plans/evaluate", json=payload)

    assert response.status_code == 422
    body = response.json()
    assert body["error"]["code"] == "VALIDATION_ERROR"
    assert body["error"]["stage"] == "validation"
    assert any(
        item["path"] == "/readiness_context/evaluated_at"
        for item in body["error"]["details"]
    )
    assert "input" not in json.dumps(body).lower()


def test_nested_user_context_is_strict() -> None:
    payload = _request().model_dump(mode="json")
    payload["readiness_context"]["user"]["mystery"] = True

    with pytest.raises(ValidationError):
        PlanEvaluateRequestV1.model_validate(payload)


def test_unsupported_report_contract_is_distinct_from_bundle_mismatch() -> None:
    bundle = _bundle()
    unsupported = bundle.model_copy(
        update={
            "ref": bundle.ref.model_copy(
                update={"domain_schema_version": "99.0.0"}
            )
        }
    )
    with pytest.raises(UnsupportedReportContractError):
        verify_report_bundle(unsupported)

    mismatched = bundle.model_copy(
        update={
            "ref": bundle.ref.model_copy(
                update={"competition_id": "cmp-other"}
            )
        }
    )
    with pytest.raises(ReportBundleError):
        verify_report_bundle(mismatched)


def test_raw_wire_fingerprint_is_checked_before_pydantic_coercion() -> None:
    payload = _request().model_dump(mode="json")
    payload["report_bundle"]["report"]["report_version"] = "3"

    response = TestClient(app).post("/api/v1/plans/evaluate", json=payload)

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "REPORT_BUNDLE_INVALID"


def test_unsupported_schema_uses_public_contract_error_code() -> None:
    payload = _request().model_dump(mode="json")
    payload["report_bundle"]["ref"]["domain_schema_version"] = "99.0.0"

    response = TestClient(app).post("/api/v1/plans/evaluate", json=payload)

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "UNSUPPORTED_REPORT_CONTRACT"


def test_jcs_rejects_lone_surrogate_object_key_cleanly() -> None:
    with pytest.raises(CanonicalJsonError):
        jcs_dumps({"\ud800": "invalid"})


def test_jcs_number_serialization_matches_rfc8785_examples() -> None:
    value = [333333333.33333329, 1e30, 4.50, 2e-3, 1e-27]

    assert jcs_dumps(value) == "[333333333.3333333,1e+30,4.5,0.002,1e-27]"
