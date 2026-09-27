"""Stable validation classification for competition source metadata."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

import apps.api.routes.competitions as competitions_route
from apps.api.main import app
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


@pytest.mark.parametrize(
    ("error_type", "status_code", "public_code"),
    [
        (InvalidSourceError, 400, "INVALID_SOURCE"),
        (SourceFetchError, 502, "SOURCE_FETCH_FAILED"),
        (SourceLimitExceededError, 413, "SOURCE_LIMIT_EXCEEDED"),
        (UnsupportedMediaTypeError, 415, "UNSUPPORTED_MEDIA_TYPE"),
        (OCRProviderUnavailableError, 503, "OCR_PROVIDER_UNAVAILABLE"),
        (OCRTimeoutError, 504, "OCR_TIMEOUT"),
        (OCRProviderError, 502, "OCR_PROVIDER_ERROR"),
        (NativeExtractionError, 422, "NATIVE_EXTRACTION_FAILED"),
        (OCRExtractionError, 422, "OCR_EXTRACTION_FAILED"),
        (CandidateNormalizationError, 500, "CANDIDATE_NORMALIZATION_FAILED"),
        (SnapshotIntegrityError, 500, "SNAPSHOT_INTEGRITY_FAILED"),
        (SnapshotBatchError, 500, "SNAPSHOT_BATCH_INVALID"),
    ],
)
def test_ingestion_and_extraction_failures_have_stable_http_mapping(
    monkeypatch,
    error_type,
    status_code: int,
    public_code: str,
) -> None:
    def fail(_request):
        raise error_type(
            "private engine detail",
            source_ref="https://private.invalid/source",
        )

    monkeypatch.setattr(competitions_route, "analyze_url", fail)
    response = TestClient(app).post(
        "/api/v1/competitions/analyze/url",
        json={
            "competition_id": "cmp-1",
            "url": "https://example.com/rules",
            "source": {
                "source_id": "src-1",
                "source_type": "official_rules",
                "authority_rank": {
                    "basis": "official_rules",
                    "tier": 1,
                },
                "scope": {"category": "all"},
                "freshness_metadata": {},
            },
        },
    )

    assert response.status_code == status_code
    body = response.json()
    assert body["error"]["code"] == public_code
    serialized = str(body)
    assert "private engine detail" not in serialized
    assert "private.invalid" not in serialized
