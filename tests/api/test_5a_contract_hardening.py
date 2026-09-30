"""Executable 5A contract hardening over the frozen public boundary."""

from __future__ import annotations

import asyncio
import json
from collections.abc import Callable
from uuid import UUID

import pytest
from fastapi import Request
from fastapi.testclient import TestClient

import apps.api.routes.competitions as competitions_route
import apps.api.routes.plans as plans_route
from apps.api.contracts import (
    CandidateRefV1,
    CompetitionAnalyzePdfMetadataV1,
    CompetitionAnalyzeResponseV1,
    CompetitionAnalyzeUrlRequestV1,
    PlanEvaluateRequestV1,
    PlanEvaluateResponseV1,
    PlanningDecisionV1,
    PlanReevaluateErrorResponseV1,
    PlanReevaluateRequestV1,
    PlanReevaluateResponseV1,
    PublicCandidateV1,
    RecommendationSetV1,
    ReevaluationTransitionV1,
)
from apps.api.errors import (
    ApiContractError,
    PlanReevaluateContractError,
    classify_plan_failure,
    unhandled_error_handler,
)
from apps.api.main import app
from apps.api.services.competition_analysis import (
    AnalysisContinuationError,
    AnalysisInputError,
    AnalysisInvariantError,
    AnalysisReconciliationError,
)
from apps.api.services.plan_evaluation import (
    PlanEvaluationAvailabilityError,
    PlanEvaluationExecutionError,
    PlanEvaluationIndeterminateError,
    PlanEvaluationInputError,
    PlanEvaluationInvariantError,
    PlanEvaluationRuntimeError,
    PlanEvaluationSolverExecutionError,
    ReportBundleError,
    UnsupportedReportContractError,
)
from apps.api.services.reevaluation import (
    ReevaluationContextInvalid,
    ReevaluationExecutionFailure,
)
from engine.extraction import (
    CandidateNormalizationError,
    InvalidSourceError,
    NativeExtractionError,
    OCRExtractionError,
    OCRProviderError,
    OCRProviderUnavailableError,
    OCRTimeoutError,
    SnapshotBatchError,
    SnapshotIntegrityError,
    SourceFetchError,
    SourceLimitExceededError,
    UnsupportedMediaTypeError,
)
from packages.contracts import (
    CanonicalFieldState,
    FeasibilityStatus,
    ReadinessStatus,
    RecommendationAction,
)
from tests.support.public_error_matrix import (
    DETAIL_ARRAY,
    HEALTH_CONTRACT,
    PUBLIC_ERROR_MATRIX,
    TRANSITION_NA,
    TRANSITION_NULL,
    TRANSITION_PASSTHROUGH,
)
from tests.support.semantic_projection import semantic_projection


def _private_ingestion(error_type):
    return error_type("private engine detail", source_ref="https://private.invalid")


ANALYSIS_FACTORIES: dict[str, Callable[[], Exception]] = {
    "AnalysisInputError": lambda: AnalysisInputError("private"),
    "AnalysisContinuationError": lambda: AnalysisContinuationError("private"),
    "UnsupportedReportContractError": lambda: UnsupportedReportContractError("private"),
    "ReportBundleError": lambda: ReportBundleError("private"),
    "InvalidSourceError": lambda: _private_ingestion(InvalidSourceError),
    "SourceFetchError": lambda: _private_ingestion(SourceFetchError),
    "SourceLimitExceededError": lambda: _private_ingestion(SourceLimitExceededError),
    "UnsupportedMediaTypeError": lambda: _private_ingestion(UnsupportedMediaTypeError),
    "OCRProviderUnavailableError": lambda: _private_ingestion(OCRProviderUnavailableError),
    "OCRTimeoutError": lambda: _private_ingestion(OCRTimeoutError),
    "OCRProviderError": lambda: _private_ingestion(OCRProviderError),
    "NativeExtractionError": lambda: _private_ingestion(NativeExtractionError),
    "OCRExtractionError": lambda: _private_ingestion(OCRExtractionError),
    "CandidateNormalizationError": lambda: _private_ingestion(CandidateNormalizationError),
    "SnapshotIntegrityError": lambda: _private_ingestion(SnapshotIntegrityError),
    "SnapshotBatchError": lambda: _private_ingestion(SnapshotBatchError),
    "AnalysisReconciliationError": lambda: AnalysisReconciliationError("private"),
    "AnalysisInvariantError": lambda: AnalysisInvariantError("private"),
}

PLAN_FACTORIES: dict[str, Callable[[], Exception]] = {
    "UnsupportedReportContractError": lambda: UnsupportedReportContractError("private"),
    "ReportBundleError": lambda: ReportBundleError("private"),
    "PlanEvaluationInputError": lambda: PlanEvaluationInputError("private"),
    "PlanEvaluationIndeterminateError": lambda: PlanEvaluationIndeterminateError("private"),
    "PlanEvaluationAvailabilityError": lambda: PlanEvaluationAvailabilityError("private"),
    "PlanEvaluationSolverExecutionError": lambda: PlanEvaluationSolverExecutionError("private"),
    "PlanEvaluationRuntimeError": lambda: PlanEvaluationRuntimeError("private"),
    "PlanEvaluationExecutionError": lambda: PlanEvaluationExecutionError("private"),
    "PlanEvaluationInvariantError": lambda: PlanEvaluationInvariantError("private"),
    "UnhandledException": lambda: RuntimeError("private"),
}


def _matrix_case(endpoint: str, failure_class: str):
    matches = [
        item
        for item in PUBLIC_ERROR_MATRIX
        if item.endpoint == endpoint and item.failure_class == failure_class
    ]
    assert len(matches) == 1
    return matches[0]


def _assert_contract(error: ApiContractError, case) -> None:
    assert error.status_code == case.http_status
    assert error.code == case.code
    assert error.stage == case.stage
    assert case.details_shape == DETAIL_ARRAY


def _assert_error_body(body: dict, *, reevaluation: bool) -> None:
    assert set(body) == ({"error", "transition"} if reevaluation else {"error"})
    error = body["error"]
    assert set(error) == {"code", "message", "stage", "details"}
    assert isinstance(error["details"], list)
    for detail in error["details"]:
        assert set(detail) == {"path", "message", "code"}
        assert all(isinstance(detail[key], str) and detail[key] for key in detail)


def test_public_error_matrix_rows_freeze_every_dimension() -> None:
    keys = [(item.endpoint, item.failure_class) for item in PUBLIC_ERROR_MATRIX]
    assert len(keys) == len(set(keys))
    assert PUBLIC_ERROR_MATRIX
    for item in PUBLIC_ERROR_MATRIX:
        assert item.endpoint.startswith(("POST ", "GET "))
        assert item.failure_class
        assert 400 <= item.http_status <= 599
        assert item.code
        assert item.stage
        assert item.details_shape == DETAIL_ARRAY
        assert item.transition in {
            TRANSITION_NA,
            TRANSITION_NULL,
            TRANSITION_PASSTHROUGH,
        }


@pytest.mark.parametrize("failure_class", sorted(ANALYSIS_FACTORIES))
def test_analysis_service_failures_match_frozen_public_matrix(failure_class: str) -> None:
    case = _matrix_case("POST /api/v1/competitions/analyze/url", failure_class)
    with pytest.raises(ApiContractError) as captured:
        competitions_route._raise_analysis_error(ANALYSIS_FACTORIES[failure_class]())
    _assert_contract(captured.value, case)


@pytest.mark.parametrize("failure_class", sorted(PLAN_FACTORIES))
def test_plan_failure_classifier_matches_frozen_public_matrix(failure_class: str) -> None:
    case = _matrix_case("POST /api/v1/plans/evaluate", failure_class)
    contract = classify_plan_failure(PLAN_FACTORIES[failure_class]())
    assert contract.status_code == case.http_status
    assert contract.code == case.code
    assert contract.stage == case.stage


@pytest.mark.parametrize(
    "failure_class",
    sorted(name for name in PLAN_FACTORIES if name != "UnhandledException"),
)
def test_reevaluation_failure_preserves_trusted_witness(
    monkeypatch,
    failure_class: str,
) -> None:
    case = _matrix_case(
        "POST /api/v1/plans/re-evaluate",
        f"ReevaluationExecutionFailure[{failure_class}]",
    )
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
            cause=PLAN_FACTORIES[failure_class](),
            transition=trusted,
        )

    monkeypatch.setattr(plans_route, "reevaluate_plan", fail)
    request = PlanReevaluateRequestV1.model_construct()
    with pytest.raises(PlanReevaluateContractError) as captured:
        plans_route.reevaluate_plan_route(request)

    _assert_contract(captured.value, case)
    assert captured.value.transition == trusted
    assert case.transition == TRANSITION_PASSTHROUGH


def test_reevaluation_context_failure_has_no_stale_transition(monkeypatch) -> None:
    case = _matrix_case(
        "POST /api/v1/plans/re-evaluate",
        "ReevaluationContextInvalid",
    )

    def fail(_request):
        raise ReevaluationContextInvalid("private")

    monkeypatch.setattr(plans_route, "reevaluate_plan", fail)
    with pytest.raises(PlanReevaluateContractError) as captured:
        plans_route.reevaluate_plan_route(PlanReevaluateRequestV1.model_construct())

    _assert_contract(captured.value, case)
    assert captured.value.transition is None
    assert case.transition == TRANSITION_NULL


def test_validation_error_envelopes_keep_detail_shape_and_transition_rule() -> None:
    client = TestClient(app)

    evaluation = client.post("/api/v1/plans/evaluate", json={})
    assert evaluation.status_code == 422
    evaluation_body = evaluation.json()
    _assert_error_body(evaluation_body, reevaluation=False)
    assert evaluation_body["error"]["code"] == "VALIDATION_ERROR"
    assert evaluation_body["error"]["stage"] == "validation"

    reevaluation = client.post("/api/v1/plans/re-evaluate", json={})
    assert reevaluation.status_code == 422
    reevaluation_body = reevaluation.json()
    _assert_error_body(reevaluation_body, reevaluation=True)
    assert reevaluation_body["error"]["code"] == "VALIDATION_ERROR"
    assert reevaluation_body["error"]["stage"] == "validation"
    assert reevaluation_body["transition"] is None


def test_pdf_form_shape_matches_frozen_error_matrix() -> None:
    case = _matrix_case(
        "POST /api/v1/competitions/analyze/pdf",
        "PdfFormValidation",
    )
    response = TestClient(app).post(
        "/api/v1/competitions/analyze/pdf",
        files={"file": ("brief.pdf", b"%PDF-1.4", "application/pdf")},
    )

    assert response.status_code == case.http_status
    body = response.json()
    _assert_error_body(body, reevaluation=False)
    assert body["error"]["code"] == case.code
    assert body["error"]["stage"] == case.stage


def test_pdf_upload_media_type_matches_frozen_error_matrix() -> None:
    case = _matrix_case(
        "POST /api/v1/competitions/analyze/pdf",
        "PdfUploadUnsupportedMediaType",
    )
    metadata = {
        "competition_id": "cmp-5a-error-matrix",
        "document_id": "doc-1",
        "source": {
            "source_id": "source-1",
            "source_type": "official_rules",
            "authority_rank": 1,
            "scope": {},
            "freshness_metadata": {},
        },
    }
    response = TestClient(app).post(
        "/api/v1/competitions/analyze/pdf",
        data={"metadata": json.dumps(metadata)},
        files={"file": ("brief.txt", b"not a pdf", "text/plain")},
    )

    assert response.status_code == case.http_status
    body = response.json()
    _assert_error_body(body, reevaluation=False)
    assert body["error"]["code"] == case.code
    assert body["error"]["stage"] == case.stage


def test_unsupported_reevaluation_contract_is_422_with_null_transition() -> None:
    client = TestClient(app)
    response = client.post(
        "/api/v1/plans/re-evaluate",
        json={
            "prior": {
                "evaluation_id": "00000000-0000-4000-8000-000000000001",
                "basis": {
                    "version": "evaluation-basis-v999",
                    "domain_schema_version": "3.0.0",
                },
            },
            "current": {},
        },
    )
    assert response.status_code == 422
    body = response.json()
    _assert_error_body(body, reevaluation=True)
    assert body["error"]["code"] == "UNSUPPORTED_REEVALUATION_CONTRACT"
    assert body["error"]["stage"] == "reevaluation"
    assert body["transition"] is None


def test_unhandled_reevaluation_error_is_internal_with_null_transition() -> None:
    request = Request(
        {
            "type": "http",
            "method": "POST",
            "path": "/api/v1/plans/re-evaluate",
            "headers": [],
        }
    )
    response = asyncio.run(
        unhandled_error_handler(request, RuntimeError("private stack"))
    )
    assert response.status_code == 500
    body = json.loads(response.body)
    _assert_error_body(body, reevaluation=True)
    assert body["error"]["code"] == "INTERNAL_ERROR"
    assert body["error"]["stage"] == "internal"
    assert body["transition"] is None
    assert "private stack" not in response.body.decode()


def test_health_contract_is_frozen() -> None:
    endpoint, status, payload = HEALTH_CONTRACT
    method, path = endpoint.split(" ", 1)
    assert method == "GET"
    response = TestClient(app).get(path)
    assert response.status_code == status
    assert response.json() == payload


def test_public_wire_field_sets_are_frozen_for_parallel_5a_5b() -> None:
    expected = {
        CompetitionAnalyzeUrlRequestV1: (
            "competition_id", "url", "source", "previous_report_bundle",
            "prior_source_artifacts",
        ),
        CompetitionAnalyzePdfMetadataV1: (
            "competition_id", "document_id", "source", "previous_report_bundle",
            "prior_source_artifacts",
        ),
        CompetitionAnalyzeResponseV1: (
            "report_bundle", "source_artifacts", "provenance", "report_changed",
        ),
        PlanEvaluateRequestV1: ("report_bundle", "readiness_context", "planning"),
        PlanEvaluateResponseV1: (
            "evaluation_id", "evaluated_at", "basis", "readiness", "planning",
        ),
        PlanReevaluateRequestV1: ("prior", "current"),
        PlanReevaluateResponseV1: ("transition", "evaluation"),
        PlanReevaluateErrorResponseV1: ("error", "transition"),
        PlanningDecisionV1: (
            "feasibility", "candidates", "allowed_actions", "reason_codes",
            "tradeoff_codes", "sensitivity_codes", "recommendation",
        ),
        CandidateRefV1: ("evaluation_id", "candidate_id"),
        PublicCandidateV1: ("ref", "work_blocks", "buffer_minutes", "assumptions"),
        RecommendationSetV1: (
            "primary_candidate", "alternative_candidates", "recommendation", "trace",
        ),
    }
    for model, fields in expected.items():
        assert tuple(model.model_fields) == fields

    assert tuple(item.value for item in ReadinessStatus) == (
        "READY_TO_EVALUATE",
        "NEEDS_REVIEW",
        "ELIGIBILITY_BLOCKED",
        "DEADLINE_PASSED",
        "INSUFFICIENT_INFORMATION",
    )
    assert tuple(item.value for item in FeasibilityStatus) == (
        "FEASIBLE",
        "FEASIBLE_WITH_TRADEOFFS",
        "TIGHT_CAPACITY",
        "NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS",
    )
    assert tuple(item.value for item in RecommendationAction) == (
        "ACCEPT",
        "CHOOSE_ALTERNATIVE",
        "EDIT_CONSTRAINTS",
        "IGNORE",
    )
    assert tuple(item.value for item in CanonicalFieldState) == (
        "VERIFIED",
        "SINGLE_SOURCE",
        "CONFLICT",
        "MISSING",
        "UNVERIFIED",
    )


def test_semantic_projection_recursively_removes_only_evaluation_identity() -> None:
    raw = {
        "evaluation_id": "run-a",
        "evaluated_at": "2026-09-27T13:20:17Z",
        "candidate": {
            "ref": {"evaluation_id": "run-a", "candidate_id": "candidate-001"},
            "task_id": "task-1",
        },
        "recommendation": {
            "primary_candidate": {
                "evaluation_id": "run-a",
                "candidate_id": "candidate-001",
            },
            "alternatives": [
                {
                    "evaluation_id": "run-a",
                    "candidate_id": "candidate-002",
                }
            ],
        },
        "basis_fingerprint": "a" * 64,
    }
    projected = semantic_projection(raw)
    serialized = json.dumps(projected)
    assert "evaluation_id" not in serialized
    assert projected["evaluated_at"] == "2026-09-27T13:20:17Z"
    assert projected["candidate"]["ref"]["candidate_id"] == "candidate-001"
    assert projected["candidate"]["task_id"] == "task-1"
    assert projected["recommendation"]["alternatives"][0]["candidate_id"] == (
        "candidate-002"
    )
    assert projected["basis_fingerprint"] == "a" * 64
