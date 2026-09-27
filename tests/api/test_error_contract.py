"""Stable validation classification for competition source metadata."""

from __future__ import annotations

from fastapi.testclient import TestClient

from apps.api.main import app


def test_url_source_metadata_failure_has_source_specific_code() -> None:
    response = TestClient(app).post(
        "/api/v1/competitions/analyze/url",
        json={
            "competition_id": "cmp-1",
            "url": "https://example.com/rules",
            "source": {
                "source_id": "",
                "source_type": "official_rules",
                "authority_rank": 1,
                "scope": {},
                "freshness_metadata": {},
            },
        },
    )

    assert response.status_code == 422
    body = response.json()
    assert body["error"]["code"] == "SOURCE_METADATA_INVALID"
    assert body["error"]["stage"] == "ingestion"
