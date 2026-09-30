"""Regression evidence for the final 5A audit gaps."""

from __future__ import annotations

import asyncio
import json
from uuid import UUID

import pytest
from fastapi import Request
from fastapi.testclient import TestClient

import apps.api.routes.plans as plans_route
from apps.api.contracts import PlanReevaluateRequestV1, ReevaluationTransitionV1
from apps.api.errors import PlanReevaluateContractError, unhandled_error_handler
from apps.api.main import app
from apps.api.services.reevaluation import ReevaluationExecutionFailure
from tests.support.public_error_matrix import (
    _ANALYSIS_FAILURES,
    _ANALYSIS_VALIDATION_FAILURES,
    ANALYSIS_ENDPOINTS,
    PLAN_FAILURES,
    PUBLIC_ERROR_MATRIX,
    TRANSITION_NULL,
    TRANSITION_PASSTHROUGH,
)


def _case(endpoint: str, failure_class: str):
    matches = [
        item
        for item in PUBLIC_ERROR_MATRIX
        if item.endpoint == endpoint and item.failure_class == failure_class
    ]
    assert len(matches) == 1
    return matches[0]


def _assert_http_case(response, case, *, reevaluation: bool = False) -> None:
    assert response.status_code == case.http_status
    body = response.json()
    assert set(body) == ({"error", "transition"} if reevaluation else {"error"})
    assert body["error"]["code"] == case.code
    assert body["error"]["stage"] == case.stage
    assert isinstance(body["error"]["details"], list)


def _valid_pdf_metadata() -> dict:
    return {
        "competition_id": "cmp-5a-metadata",
        "document_id": "doc-5a",
        "source": {
            "source_id": "source-5a",
            "source_type": "official_rules",
            "authority_rank": {"tier": 1},
            "scope": {},
            "freshness_metadata": {},
        },
    }


def test_public_error_matrix_is_closed_over_every_frozen_case() -> None:
    expected = {
        (endpoint, failure)
        for endpoint in ANALYSIS_ENDPOINTS
        for failure, _status, _code, _stage in (
            *_ANALYSIS_VALIDATION_FAILURES,
            *_ANALYSIS_FAILURES,
        )
    }
    expected.update(
        {
            ("POST /api/v1/competitions/analyze/pdf", "PdfFormValidation"),
            ("POST /api/v1/competitions/analyze/pdf", "PdfMetadataInvalidJson"),
            ("POST /api/v1/competitions/analyze/pdf", "PdfMetadataValidation"),
            (
                "POST /api/v1/competitions/analyze/pdf",
                "PdfMetadataValidation[source]",
            ),
            (
                "POST /api/v1/competitions/analyze/pdf",
                "PdfUploadUnsupportedMediaType",
            ),
            ("POST /api/v1/plans/evaluate", "RequestValidationError"),
            (
                "POST /api/v1/plans/evaluate",
                "UnsupportedReportContractValidation",
            ),
            (
                "POST /api/v1/plans/evaluate",
                "ReportBundleInvalidValidation",
            ),
            ("POST /api/v1/plans/re-evaluate", "ReevaluationContextInvalid"),
            ("POST /api/v1/plans/re-evaluate", "UnhandledException"),
            ("POST /api/v1/plans/re-evaluate", "RequestValidationError"),
            (
                "POST /api/v1/plans/re-evaluate",
                "UnsupportedReevaluationContract",
            ),
            (
                "POST /api/v1/plans/re-evaluate",
                "UnsupportedReportContractValidation",
            ),
            (
                "POST /api/v1/plans/re-evaluate",
                "ReportBundleInvalidValidation",
            ),
        }
    )
    expected.update(
        {
            ("POST /api/v1/plans/evaluate", failure)
            for failure, _status, _code, _stage in PLAN_FAILURES
        }
    )
    expected.update(
        {
            (
                "POST /api/v1/plans/re-evaluate",
                f"ReevaluationExecutionFailure[{failure}]",
            )
            for failure, _status, _code, _stage in PLAN_FAILURES
        }
    )

    actual = {(item.endpoint, item.failure_class) for item in PUBLIC_ERROR_MATRIX}
    assert actual == expected


@pytest.mark.parametrize("endpoint", ANALYSIS_ENDPOINTS)
def test_analysis_unhandled_exception_rows_are_executable(endpoint: str) -> None:
    method, path = endpoint.split(" ", 1)
    request = Request(
        {
            "type": "http",
            "method": method,
            "path": path,
            "headers": [],
        }
    )
    response = asyncio.run(
        unhandled_error_handler(request, RuntimeError("private analysis detail"))
    )
    case = _case(endpoint, "UnhandledException")
    assert response.status_code == case.http_status
    body = json.loads(response.body)
    assert body["error"]["code"] == case.code
    assert body["error"]["stage"] == case.stage
    assert "private analysis detail" not in response.body.decode()


def test_pdf_invalid_metadata_json_matches_explicit_matrix_row() -> None:
    case = _case(
        "POST /api/v1/competitions/analyze/pdf",
        "PdfMetadataInvalidJson",
    )
    response = TestClient(app).post(
        "/api/v1/competitions/analyze/pdf",
        data={"metadata": "{"},
        files={"file": ("brief.pdf", b"%PDF-1.4", "application/pdf")},
    )
    _assert_http_case(response, case)


def test_pdf_generic_metadata_validation_matches_explicit_matrix_row() -> None:
    metadata = _valid_pdf_metadata()
    metadata.pop("competition_id")
    case = _case(
        "POST /api/v1/competitions/analyze/pdf",
        "PdfMetadataValidation",
    )
    response = TestClient(app).post(
        "/api/v1/competitions/analyze/pdf",
        data={"metadata": json.dumps(metadata)},
        files={"file": ("brief.pdf", b"%PDF-1.4", "application/pdf")},
    )
    _assert_http_case(response, case)


def test_pdf_source_metadata_validation_matches_explicit_matrix_row() -> None:
    metadata = _valid_pdf_metadata()
    metadata["source"].pop("source_id")
    case = _case(
        "POST /api/v1/competitions/analyze/pdf",
        "PdfMetadataValidation[source]",
    )
    response = TestClient(app).post(
        "/api/v1/competitions/analyze/pdf",
        data={"metadata": json.dumps(metadata)},
        files={"file": ("brief.pdf", b"%PDF-1.4", "application/pdf")},
    )
    _assert_http_case(response, case)


def test_unknown_failure_after_stale_witness_preserves_transition(monkeypatch) -> None:
    trusted = ReevaluationTransitionV1(
        kind="SUPERSEDED",
        prior_evaluation_id=UUID("00000000-0000-4000-8000-000000000001"),
        prior_basis_fingerprint="a" * 64,
        current_basis_fingerprint="b" * 64,
        prior_evaluation_freshness="STALE",
        change_reasons=("PLANNING_BASIS_CHANGED",),
    )

    def fail(_request):
        raise ReevaluationExecutionFailure(
            cause=RuntimeError("private downstream detail"),
            transition=trusted,
        )

    monkeypatch.setattr(plans_route, "reevaluate_plan", fail)
    with pytest.raises(PlanReevaluateContractError) as captured:
        plans_route.reevaluate_plan_route(PlanReevaluateRequestV1.model_construct())

    case = _case(
        "POST /api/v1/plans/re-evaluate",
        "ReevaluationExecutionFailure[UnhandledException]",
    )
    error = captured.value
    assert error.status_code == case.http_status == 500
    assert error.code == case.code == "INTERNAL_ERROR"
    assert error.stage == case.stage == "internal"
    assert error.transition == trusted
    assert case.transition == TRANSITION_PASSTHROUGH


def test_pre_witness_unhandled_reevaluation_stays_transition_null() -> None:
    case = _case("POST /api/v1/plans/re-evaluate", "UnhandledException")
    request = Request(
        {
            "type": "http",
            "method": "POST",
            "path": "/api/v1/plans/re-evaluate",
            "headers": [],
        }
    )
    response = asyncio.run(
        unhandled_error_handler(request, RuntimeError("private pre-witness detail"))
    )
    assert response.status_code == case.http_status
    body = json.loads(response.body)
    assert body["error"]["code"] == case.code
    assert body["error"]["stage"] == case.stage
    assert body["transition"] is None
    assert case.transition == TRANSITION_NULL
