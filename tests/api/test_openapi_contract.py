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
