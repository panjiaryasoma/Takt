"""Semantic source metadata must fail before retrieval or reconciliation."""

from fastapi.testclient import TestClient

from apps.api.main import app


def test_semantically_invalid_source_metadata_is_422_without_fetch() -> None:
    response = TestClient(app).post(
        "/api/v1/competitions/analyze/url",
        json={
            "competition_id": "cmp-1",
            "url": "https://example.test/should-not-fetch",
            "source": {
                "source_id": "src-1",
                "source_type": "official_rules",
                "authority_rank": {
                    "basis": "secondary",
                    "tier": 1,
                },
                "scope": {"category": "all"},
                "freshness_metadata": {
                    "effective_at": "2026-09-01T00:00:00Z",
                    "supersedes_source_ids": [],
                },
            },
        },
    )

    assert response.status_code == 422
    body = response.json()
    assert body["error"]["code"] == "SOURCE_METADATA_INVALID"
    assert body["error"]["stage"] == "ingestion"
