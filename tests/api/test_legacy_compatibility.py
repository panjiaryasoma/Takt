"""Regression coverage for legacy API compatibility during Issue 4A."""

from fastapi.testclient import TestClient

from apps.api.main import app


def test_legacy_triage_still_accepts_client_evaluated_at() -> None:
    response = TestClient(app).post(
        "/api/v1/triage",
        json={
            "evaluated_at": "2026-09-27T00:00:00Z",
            "submission_deadline": "2026-09-30T23:45:00Z",
            "has_applicable_deadline_extension": False,
            "eligibility": {
                "minimum_age": None,
                "requires_student": False,
                "allowed_regions": ["global"],
            },
            "user": {
                "age": None,
                "student_status": None,
                "country": None,
            },
            "unresolved_critical_fields": [],
            "mandatory_information_complete": True,
        },
    )

    assert response.status_code == 200
    assert response.json()["status"] == "READY_TO_EVALUATE"


def test_root_health_route_is_preserved() -> None:
    response = TestClient(app).get("/health")

    assert response.status_code == 200
