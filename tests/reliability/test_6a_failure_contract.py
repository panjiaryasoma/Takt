"""Every 5A public error row has one cross-language recovery policy."""

import asyncio
import json

import httpx
import pytest
from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.testclient import TestClient

import apps.api.routes.competitions as competitions_route
import apps.api.routes.plans as plans_route
from apps.api.contracts import (
    PlanEvaluateRequestV1,
    PlanReevaluateRequestV1,
    ReevaluationTransitionV1,
)
from apps.api.errors import (
    ApiContractError,
    PlanReevaluateContractError,
    api_contract_error_handler,
    reevaluation_contract_error_handler,
    request_validation_error_handler,
    unhandled_error_handler,
)
from apps.api.main import app
from apps.api.services.reevaluation import ReevaluationContextInvalid, ReevaluationExecutionFailure
from tests.api.test_5a_contract_hardening import ANALYSIS_FACTORIES, PLAN_FACTORIES
from tests.reliability.support import PRIVATE_SENTINEL, assert_public_failure, pdf_metadata
from tests.support.public_error_matrix import PUBLIC_ERROR_MATRIX, TRANSITION_PASSTHROUGH
from tests.support.recovery_policy import POLICY_PATH, load_recovery_policy, recovery_for

POLICY = load_recovery_policy()


def _wire(response):
    return httpx.Response(response.status_code, content=response.body)


@pytest.mark.parametrize(
    "case", PUBLIC_ERROR_MATRIX, ids=lambda row: f"{row.endpoint}:{row.failure_class}"
)
def test_public_error_and_python_recovery_parity(case, monkeypatch):
    policies = [
        row
        for row in POLICY.values()
        if row["contract_key"] == case.failure_class and case.endpoint in row["endpoints"]
    ]
    assert len(policies) == 1
    policy = policies[0]
    assert recovery_for(policy["scenario_id"]) == policy["recovery_class"]
    method, path = case.endpoint.split(" ", 1)
    request = Request({"type": "http", "method": method, "path": path, "headers": []})
    failure = case.failure_class
    trusted = None

    if failure.startswith("Pdf"):
        metadata = pdf_metadata().model_dump(mode="json")
        kwargs = {
            "data": {"metadata": json.dumps(metadata)},
            "files": {"file": ("test.pdf", b"%PDF-1.4", "application/pdf")},
        }
        if failure == "PdfFormValidation":
            kwargs["data"]["extra"] = "unexpected"
        elif failure == "PdfMetadataInvalidJson":
            kwargs["data"]["metadata"] = "{"
        elif failure in {"PdfMetadataValidation", "PdfMetadataValidation[source]"}:
            if failure.endswith("[source]"):
                metadata["source"].pop("source_id")
            else:
                metadata.pop("competition_id")
            kwargs["data"]["metadata"] = json.dumps(metadata)
        elif failure == "PdfUploadUnsupportedMediaType":
            kwargs["files"]["file"] = ("test.txt", b"not PDF", "text/plain")
        else:
            pytest.fail(f"Uncovered public failure: {failure}")
        with TestClient(app) as client:
            response = client.post(path, **kwargs)
    elif "Validation" in failure or failure == "UnsupportedReevaluationContract":
        error_type = {
            "UnsupportedReportContractValidation": "unsupported_report_contract",
            "ReportBundleInvalidValidation": "report_bundle_invalid",
            "UnsupportedReevaluationContract": "unsupported_reevaluation_contract",
        }.get(failure, "missing")
        location = ("body", "source", "source_id") if failure.endswith("[source]") else ("body",)
        error = RequestValidationError(
            [
                {
                    "type": error_type,
                    "loc": location,
                    "msg": "Invalid request",
                    "input": PRIVATE_SENTINEL,
                }
            ]
        )
        response = _wire(asyncio.run(request_validation_error_handler(request, error)))
    elif failure == "UnhandledException":
        response = _wire(
            asyncio.run(unhandled_error_handler(request, RuntimeError(PRIVATE_SENTINEL)))
        )
    else:
        if "competitions/analyze" in path:
            error = ANALYSIS_FACTORIES[failure]()
            invoke = lambda: competitions_route._raise_analysis_error(error)
        else:
            if failure.startswith("ReevaluationExecutionFailure["):
                cause = PLAN_FACTORIES[failure[len("ReevaluationExecutionFailure[") : -1]]()
                trusted = ReevaluationTransitionV1(
                    kind="SUPERSEDED",
                    prior_evaluation_id="00000000-0000-4000-8000-000000000001",
                    prior_basis_fingerprint="a" * 64,
                    current_basis_fingerprint="b" * 64,
                    prior_evaluation_freshness="STALE",
                    change_reasons=("PLANNING_BASIS_CHANGED",),
                )
                error = ReevaluationExecutionFailure(cause=cause, transition=trusted)
            elif failure == "ReevaluationContextInvalid":
                error = ReevaluationContextInvalid(PRIVATE_SENTINEL)
            else:
                error = PLAN_FACTORIES[failure]()

            def fail(_request):
                raise error

            if path.endswith("/re-evaluate"):
                monkeypatch.setattr(plans_route, "reevaluate_plan", fail)
                invoke = lambda: plans_route.reevaluate_plan_route(
                    PlanReevaluateRequestV1.model_construct()
                )
            else:
                monkeypatch.setattr(plans_route, "evaluate_plan", fail)
                invoke = lambda: plans_route.evaluate_plan_route(
                    PlanEvaluateRequestV1.model_construct()
                )
        if not isinstance(error, ReevaluationExecutionFailure):
            error.args = (PRIVATE_SENTINEL,)
        with pytest.raises(ApiContractError) as captured:
            invoke()
        public_error = captured.value
        handler = (
            reevaluation_contract_error_handler
            if isinstance(public_error, PlanReevaluateContractError)
            else api_contract_error_handler
        )
        response = _wire(asyncio.run(handler(request, public_error)))

    assert_public_failure(
        response,
        case.endpoint,
        failure,
        transition=trusted.model_dump(mode="json") if trusted else None,
    )
    assert (trusted is not None) == (case.transition == TRANSITION_PASSTHROUGH)
    assert "recovery_class" not in response.text


def test_recovery_artifact_is_closed_and_contains_no_second_error_catalog():
    raw = json.loads(POLICY_PATH.read_text())
    assert set(raw["recovery_classes"]) == {
        "FIX_INPUT",
        "RETRY_SAME_INPUT",
        "REUPLOAD_SOURCE",
        "EDIT_CONSTRAINTS",
        "REEVALUATE",
        "RELOAD_CONTEXT",
        "NO_AUTOMATIC_RECOVERY",
    }
    assert all(
        not {"http_status", "code", "stage", "details", "transition"} & row.keys()
        for row in raw["scenarios"]
    )
    with pytest.raises(KeyError):
        recovery_for("UNRECOGNIZED_SCENARIO")


@pytest.mark.parametrize("mutation", ["version", "duplicate", "orphan", "missing", "code", "class"])
def test_invalid_recovery_policy_fails_closed(tmp_path, mutation):
    raw = json.loads(POLICY_PATH.read_text())
    if mutation == "version":
        raw["version"] = "recovery-policy-v999"
    elif mutation == "duplicate":
        raw["scenarios"].append(raw["scenarios"][0])
    elif mutation == "orphan":
        raw["scenarios"][0]["contract_key"] = "UnknownError"
    elif mutation == "missing":
        raw["scenarios"].pop(0)
    elif mutation == "code":
        raw["scenarios"][0]["code"] = "SECOND_ERROR_CATALOG"
    else:
        raw["scenarios"][0]["recovery_class"] = "AUTO_ACCEPT"
    path = tmp_path / "invalid.json"
    path.write_text(json.dumps(raw))
    with pytest.raises(ValueError):
        load_recovery_policy(path)
