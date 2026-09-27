"""Behavioral acceptance tests for public competition analysis."""

from __future__ import annotations

import json

import httpx
import pymupdf
import pytest
from fastapi.testclient import TestClient

import apps.api.routes.competitions as competitions_route
from apps.api.contracts import (
    CompetitionAnalyzePdfMetadataV1,
    CompetitionAnalyzeUrlRequestV1,
    SourceMetadataV1,
)
from apps.api.main import app
from apps.api.services.competition_analysis import analyze_pdf, analyze_url
from engine.extraction import OCRTextBlock, SourceFetchError
from packages.contracts import (
    CanonicalFieldState,
    ExtractionPath,
    SourceType,
)


class _StaticOCRProvider:
    provider_id = "api-fixture-ocr"
    provider_version = "1"
    language = "eng"
    page_segmentation_mode = 6

    def __init__(self, text: str) -> None:
        self.text = text

    def extract_page(
        self,
        image_bytes: bytes,
        *,
        page_number: int,
        timeout_seconds: float,
    ) -> tuple[OCRTextBlock, ...]:
        del image_bytes, timeout_seconds
        return (
            OCRTextBlock(
                locator=f"page:{page_number}:api-fixture:1",
                text=self.text,
                page_number=page_number,
                confidence=0.99,
            ),
        )


def _source(source_id: str = "src-api") -> SourceMetadataV1:
    return SourceMetadataV1(
        source_id=source_id,
        source_type=SourceType.OFFICIAL_RULES,
        authority_rank={"basis": "official_rules", "tier": 1},
        scope={"category": "all"},
        freshness_metadata={
            "effective_at": "2026-09-01T00:00:00Z",
            "supersedes_source_ids": [],
        },
    )


def _url_request() -> CompetitionAnalyzeUrlRequestV1:
    return CompetitionAnalyzeUrlRequestV1(
        competition_id="cmp-analysis",
        url="https://example.test/rules",
        source=_source(),
    )


def _pdf_bytes(text: str) -> bytes:
    document = pymupdf.open()
    page = document.new_page()
    page.insert_text((72, 72), text)
    payload = document.tobytes()
    document.close()
    return payload


def test_successful_empty_url_extraction_returns_domain_missing_and_audit_run(
    monkeypatch,
) -> None:
    html = b"<html><body>Nothing relevant here</body></html>"

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html"},
            content=html,
            request=request,
        )

    monkeypatch.setattr(
        "engine.extraction.native.validate_public_http_target",
        lambda _url: None,
    )
    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        result = analyze_url(_url_request(), client=client)

    deadline = result.report_bundle.report.canonical_fields["submission_deadline"]
    assert deadline.state is CanonicalFieldState.MISSING
    assert result.provenance.evidence == ()
    assert len(result.provenance.sources) == 1
    assert result.provenance.sources[0].retrieved_at.tzinfo is not None
    assert len(result.provenance.extraction_runs) == 1
    run = result.provenance.extraction_runs[0]
    assert run.extraction_path is ExtractionPath.NATIVE
    assert run.extractor_version


def test_canonical_evidence_references_are_resolved_by_provenance(
    monkeypatch,
) -> None:
    html = b"<html><body>Team size: 1 to 4 members</body></html>"

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html"},
            content=html,
            request=request,
        )

    monkeypatch.setattr(
        "engine.extraction.native.validate_public_http_target",
        lambda _url: None,
    )
    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        result = analyze_url(_url_request(), client=client)

    available = {item.evidence_id for item in result.provenance.evidence}
    referenced = {
        evidence_id
        for field in result.report_bundle.report.canonical_fields.values()
        for evidence_id in field.evidence_ids
    }
    assert referenced
    assert referenced <= available


def test_pdf_native_ocr_disagreement_remains_domain_conflict_with_both_runs() -> None:
    metadata = CompetitionAnalyzePdfMetadataV1(
        competition_id="cmp-pdf",
        document_id="rules.pdf",
        source=_source(),
    )
    content = _pdf_bytes(
        "Submission deadline: September 30 2026 at 23:59 WIB"
    )
    result = analyze_pdf(
        metadata,
        content,
        ocr_provider=_StaticOCRProvider(
            "Submission deadline: October 1 2026 at 23:59 WIB"
        ),
    )

    deadline = result.report_bundle.report.canonical_fields["submission_deadline"]
    assert deadline.state is CanonicalFieldState.CONFLICT
    assert {
        item.extraction_path for item in result.provenance.extraction_runs
    } == {ExtractionPath.NATIVE, ExtractionPath.OCR}


def test_source_fetch_failure_maps_to_public_error_without_internal_text(
    monkeypatch,
) -> None:
    def fail(request: CompetitionAnalyzeUrlRequestV1):
        del request
        raise SourceFetchError(
            "secret upstream stack detail",
            source_ref="https://private.example/failure",
        )

    monkeypatch.setattr(competitions_route, "analyze_url", fail)
    response = TestClient(app).post(
        "/api/v1/competitions/analyze/url",
        json=_url_request().model_dump(mode="json"),
    )

    assert response.status_code == 502
    body = response.json()
    assert body["error"]["code"] == "SOURCE_FETCH_FAILED"
    assert body["error"]["stage"] == "ingestion"
    serialized = json.dumps(body)
    assert "secret upstream stack detail" not in serialized
    assert "private.example" not in serialized


def test_sequential_analysis_preserves_full_multi_source_reconciliation(
    monkeypatch,
) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/a"):
            content = b"<html><body>Team size: 1 to 4 members</body></html>"
        else:
            content = b"<html><body>No supported competition facts here</body></html>"
        return httpx.Response(
            200,
            headers={"content-type": "text/html"},
            content=content,
            request=request,
        )

    monkeypatch.setattr(
        "engine.extraction.native.validate_public_http_target",
        lambda _url: None,
    )

    first_request = CompetitionAnalyzeUrlRequestV1(
        competition_id="cmp-multi",
        url="https://example.test/a",
        source=_source("src-a"),
    )
    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        first = analyze_url(first_request, client=client)
        first_wire = json.loads(
            json.dumps(first.model_dump(mode="json", warnings=False))
        )
        second_request = CompetitionAnalyzeUrlRequestV1.model_validate(
            {
                "competition_id": "cmp-multi",
                "url": "https://example.test/b",
                "source": _source("src-b").model_dump(mode="json"),
                "previous_report_bundle": first_wire["report_bundle"],
                "prior_source_artifacts": first_wire["source_artifacts"],
            }
        )
        second = analyze_url(second_request, client=client)

    team_size = second.report_bundle.report.canonical_fields["team_size"]
    assert team_size.state is CanonicalFieldState.SINGLE_SOURCE
    assert second.report_bundle.report.source_ids == ["src-a", "src-b"]
    assert tuple(
        item.source.source_id for item in second.source_artifacts
    ) == ("src-a", "src-b")
    assert tuple(
        item.source_id for item in second.provenance.sources
    ) == ("src-a", "src-b")
    available = {item.evidence_id for item in second.provenance.evidence}
    assert set(team_size.evidence_ids) <= available


def test_previous_report_requires_complete_prior_source_artifacts(
    monkeypatch,
) -> None:
    html = b"<html><body>Team size: 1 to 4 members</body></html>"

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html"},
            content=html,
            request=request,
        )

    monkeypatch.setattr(
        "engine.extraction.native.validate_public_http_target",
        lambda _url: None,
    )
    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        first = analyze_url(_url_request(), client=client)
        invalid = CompetitionAnalyzeUrlRequestV1(
            competition_id="cmp-analysis",
            url="https://example.test/rules",
            source=_source(),
            previous_report_bundle=first.report_bundle,
            prior_source_artifacts=(),
        )
        with pytest.raises(
            ValueError,
            match="prior source artifacts must exactly cover",
        ):
            analyze_url(invalid, client=client)
