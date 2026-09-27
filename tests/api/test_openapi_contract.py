"""OpenAPI must expose the locked Issue 4A product request surfaces."""

from fastapi.testclient import TestClient

from apps.api.main import app


def test_pdf_analysis_openapi_declares_multipart_request_body() -> None:
    document = TestClient(app).get("/openapi.json").json()
    operation = document["paths"]["/api/v1/competitions/analyze/pdf"]["post"]
    content = operation["requestBody"]["content"]

    assert "multipart/form-data" in content
    schema = content["multipart/form-data"]["schema"]
    assert schema


def test_product_evaluate_openapi_declares_json_request_and_response() -> None:
    document = TestClient(app).get("/openapi.json").json()
    operation = document["paths"]["/api/v1/plans/evaluate"]["post"]

    assert "application/json" in operation["requestBody"]["content"]
    assert "200" in operation["responses"]


def _assert_error_schema(operation: dict, status_code: int) -> None:
    response = operation["responses"][str(status_code)]
    schema = response["content"]["application/json"]["schema"]
    assert schema["$ref"].endswith("/ApiErrorResponseV1")


def test_product_openapi_error_schemas_match_runtime_envelope() -> None:
    document = TestClient(app).get("/openapi.json").json()

    plan = document["paths"]["/api/v1/plans/evaluate"]["post"]
    for status_code in (422, 500, 503):
        _assert_error_schema(plan, status_code)

    for path in (
        "/api/v1/competitions/analyze/url",
        "/api/v1/competitions/analyze/pdf",
    ):
        operation = document["paths"][path]["post"]
        for status_code in (400, 413, 415, 422, 500, 502, 503, 504):
            _assert_error_schema(operation, status_code)


def test_reevaluate_openapi_declares_specialized_success_and_error_contracts() -> None:
    document = TestClient(app).get("/openapi.json").json()
    operation = document["paths"]["/api/v1/plans/re-evaluate"]["post"]

    success_schema = operation["responses"]["200"]["content"]["application/json"]["schema"]
    assert success_schema["$ref"].endswith("/PlanReevaluateResponseV1")

    for status_code in (409, 422, 500, 503):
        response = operation["responses"][str(status_code)]
        schema = response["content"]["application/json"]["schema"]
        assert schema["$ref"].endswith("/PlanReevaluateErrorResponseV1")
