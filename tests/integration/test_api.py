from fastapi.testclient import TestClient

from apps.api.main import app

client = TestClient(app)


def test_health() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_triage_endpoint_ready() -> None:
    response = client.post(
        "/api/v1/triage",
        json={
            "evaluated_at": "2026-09-21T08:00:00Z",
            "submission_deadline": "2026-09-30T23:45:00-07:00",
            "eligibility": {
                "minimum_age": 18,
                "requires_student": True,
                "allowed_regions": ["global"],
            },
            "user": {
                "age": 21,
                "student_status": True,
                "country": "Indonesia",
            },
            "unresolved_critical_fields": [],
            "mandatory_information_complete": True,
        },
    )
    assert response.status_code == 200
    assert response.json()["status"] == "READY_TO_EVALUATE"


def test_triage_endpoint_rejects_naive_evaluated_at() -> None:
    response = client.post(
        "/api/v1/triage",
        json={
            "evaluated_at": "2026-09-21T08:00:00",
            "submission_deadline": "2026-09-30T23:45:00+07:00",
        },
    )

    assert response.status_code == 422


def test_triage_endpoint_rejects_naive_submission_deadline() -> None:
    response = client.post(
        "/api/v1/triage",
        json={
            "evaluated_at": "2026-09-21T08:00:00+07:00",
            "submission_deadline": "2026-09-30T23:45:00",
        },
    )

    assert response.status_code == 422
