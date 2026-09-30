"""Adversarial evidence at real ingestion/extraction boundaries."""

import subprocess

import httpx
import pymupdf
import pytest
from fastapi.testclient import TestClient

import apps.api.routes.competitions as competitions_route
import engine.extraction.ocr.service as ocr_service
from apps.api.main import app
from apps.api.services.competition_analysis import analyze_pdf, analyze_url
from apps.api.services.plan_evaluation import evaluate_plan
from engine.extraction import (
    OCRProviderError,
    OCRProviderUnavailableError,
    OCRTimeoutError,
    SourceLimitExceededError,
    TesseractOCRProvider,
    create_pdf_snapshot,
    extract_native_snapshot,
    extract_snapshot,
    fetch_url_snapshot,
    native,
)
from engine.extraction.ocr import tesseract
from packages.contracts import CanonicalFieldState, ReadinessStatus
from tests.reliability.support import (
    PDF_ENDPOINT,
    PRIVATE_SENTINEL,
    URL_ENDPOINT,
    EmptyOCR,
    assert_public_failure,
    clock,
    mock_source_client,
    pdf_bytes,
    pdf_metadata,
    plan_request,
    public_dns,
    source_context,
    url_request,
)


@pytest.mark.parametrize("value", [None, "", 123, []])
def test_invalid_url_request_is_validation_before_ingestion(monkeypatch, value):
    calls = []
    monkeypatch.setattr(competitions_route, "analyze_url", lambda *args: calls.append(args))
    payload = url_request().model_dump(mode="json")
    if value is None:
        payload.pop("url")
    else:
        payload["url"] = value
    with TestClient(app) as client:
        response = client.post(URL_ENDPOINT.split()[1], json=payload)
    assert_public_failure(response, URL_ENDPOINT, "RequestValidationError")
    assert calls == []


@pytest.mark.parametrize(
    "url",
    [
        "file:///etc/hosts",
        "http://localhost/rules",
        "http://127.0.0.1/rules",
        "http://10.0.0.1/rules",
        "http://[::1]/rules",
        "https://private.example/rules",
    ],
)
def test_valid_shaped_unsafe_url_fails_before_network(monkeypatch, url):
    requests = []
    monkeypatch.setattr(
        "engine.extraction.url_security.socket.getaddrinfo",
        lambda *_a, **_k: [(2, 1, 6, "", ("10.1.2.3", 443))],
    )
    with mock_source_client(b"unreachable", requests=requests) as transport:
        monkeypatch.setattr(
            competitions_route,
            "analyze_url",
            lambda request: analyze_url(request, client=transport),
        )
        with TestClient(app) as client:
            response = client.post(
                URL_ENDPOINT.split()[1],
                json={
                    **url_request().model_dump(mode="json"),
                    "url": url,
                },
            )
    assert_public_failure(response, URL_ENDPOINT, "InvalidSourceError")
    assert requests == []


@pytest.mark.parametrize("failure", ["timeout", "network", "http"])
def test_retrieval_failure_is_never_empty_extraction(monkeypatch, failure):
    monkeypatch.setattr("engine.extraction.url_security.socket.getaddrinfo", public_dns)
    calls = []

    def respond(request):
        calls.append(request)
        if failure == "timeout":
            raise httpx.ReadTimeout(PRIVATE_SENTINEL, request=request)
        if failure == "network":
            raise httpx.ConnectError(PRIVATE_SENTINEL, request=request)
        return httpx.Response(503, content=PRIVATE_SENTINEL, request=request)

    with httpx.Client(transport=httpx.MockTransport(respond)) as transport:
        monkeypatch.setattr(
            competitions_route,
            "analyze_url",
            lambda request: analyze_url(request, client=transport),
        )
        with TestClient(app) as client:
            response = client.post(
                URL_ENDPOINT.split()[1], json=url_request().model_dump(mode="json")
            )
    assert_public_failure(response, URL_ENDPOINT, "SourceFetchError")
    assert len(calls) == 1


@pytest.mark.parametrize("content", [b"", b"not a PDF", b"%PDF-1.7\ncorrupt"])
def test_unreadable_uploaded_pdf_has_exact_native_error(content):
    with TestClient(app) as client:
        response = client.post(
            PDF_ENDPOINT.split()[1],
            data={"metadata": pdf_metadata().model_dump_json()},
            files={"file": ("bad.pdf", content, "application/pdf")},
        )
    assert_public_failure(response, PDF_ENDPOINT, "NativeExtractionError")


@pytest.mark.parametrize("image_only", [False, True])
def test_valid_pdf_without_facts_is_success_and_readiness_owns_missing(image_only):
    content = pdf_bytes(image_only=image_only)
    result = analyze_pdf(pdf_metadata(), content, ocr_provider=EmptyOCR())
    assert len(result.provenance.extraction_runs) == 2
    reports = result.source_artifacts[0].candidate_reports
    assert len(reports) == 2
    assert all(not report.fields for report in reports)
    assert all(
        field.state is CanonicalFieldState.MISSING
        for field in result.report_bundle.report.canonical_fields.values()
    )
    request = plan_request(effort_minutes=60).model_copy(
        update={"report_bundle": result.report_bundle}
    )
    evaluated = evaluate_plan(request, clock=clock)
    assert evaluated.readiness.status is ReadinessStatus.INSUFFICIENT_INFORMATION
    assert evaluated.planning is None and evaluated.basis.planning is None
    if image_only:
        snapshot = create_pdf_snapshot("image.pdf", content, context=source_context())
        native_document = extract_native_snapshot(snapshot)
        assert native_document.blocks == ()
        assert native_document.pages_without_native_text == (1,)


@pytest.mark.parametrize(
    "error_type,contract_key",
    [
        (OCRTimeoutError, "OCRTimeoutError"),
        (OCRProviderUnavailableError, "OCRProviderUnavailableError"),
        (OCRProviderError, "OCRProviderError"),
        (RuntimeError, "OCRExtractionError"),
    ],
)
def test_ocr_failure_cannot_be_masked_by_successful_native_facts(
    monkeypatch, error_type, contract_key
):
    class BrokenProvider(EmptyOCR):
        def extract_page(self, *_args, **_kwargs):
            raise error_type(PRIVATE_SENTINEL)

    monkeypatch.setattr(
        competitions_route,
        "analyze_pdf",
        lambda metadata, content: analyze_pdf(metadata, content, ocr_provider=BrokenProvider()),
    )
    with TestClient(app) as client:
        response = client.post(
            PDF_ENDPOINT.split()[1],
            data={"metadata": pdf_metadata().model_dump_json()},
            files={
                "file": ("good.pdf", pdf_bytes(text="Team size: 1 to 4 members"), "application/pdf")
            },
        )
    assert_public_failure(response, PDF_ENDPOINT, contract_key)


def test_source_byte_cap_precedes_pdf_parse_and_ocr(monkeypatch):
    def forbidden(*_args, **_kwargs):
        pytest.fail("Oversized source reached PDF parsing")

    monkeypatch.setattr("engine.extraction.snapshot_pipeline.extract_native_snapshot", forbidden)
    with TestClient(app) as client:
        response = client.post(
            PDF_ENDPOINT.split()[1],
            data={"metadata": pdf_metadata().model_dump_json()},
            files={"file": ("large.pdf", b"x" * (20 * 1024 * 1024 + 1), "application/pdf")},
        )
    assert_public_failure(response, PDF_ENDPOINT, "SourceLimitExceededError")


def test_url_declared_size_cap_precedes_body_consumption(monkeypatch):
    monkeypatch.setattr("engine.extraction.url_security.socket.getaddrinfo", public_dns)

    class ForbiddenBody(httpx.SyncByteStream):
        def __iter__(self):
            pytest.fail("Declared oversized response body was consumed")
            yield b""  # pragma: no cover

    def respond(request):
        return httpx.Response(
            200,
            headers={
                "content-type": "application/pdf",
                "content-length": str(20 * 1024 * 1024 + 1),
            },
            stream=ForbiddenBody(),
            request=request,
        )

    with (
        httpx.Client(transport=httpx.MockTransport(respond)) as transport,
        pytest.raises(SourceLimitExceededError),
    ):
        fetch_url_snapshot(url_request().url, context=source_context(), client=transport)


@pytest.mark.parametrize("pages", [250, 251])
def test_native_pdf_page_budget_exact_boundary(pages):
    snapshot = create_pdf_snapshot(
        "pages.pdf", pdf_bytes(pages=pages, text=""), context=source_context()
    )
    if pages == 250:
        assert extract_native_snapshot(snapshot).page_count == 250
    else:
        with pytest.raises(SourceLimitExceededError):
            extract_native_snapshot(snapshot)


@pytest.mark.parametrize("pages", [50, 51])
def test_ocr_pdf_page_budget_exact_boundary(monkeypatch, pages):
    seen = []

    class CountingProvider(EmptyOCR):
        def extract_page(self, image_bytes, *, page_number, timeout_seconds):
            seen.append(page_number)
            return ()

    snapshot = create_pdf_snapshot(
        "ocr-pages.pdf", pdf_bytes(pages=pages, text=""), context=source_context()
    )
    if pages == 50:
        assert (
            extract_snapshot(snapshot, ocr_provider=CountingProvider()).ocr_document.page_count
            == 50
        )
        assert len(seen) == 50
    else:

        def forbidden(*_args, **_kwargs):
            pytest.fail("Over-budget PDF was rasterized")

        monkeypatch.setattr(pymupdf.Page, "get_pixmap", forbidden)
        with pytest.raises(SourceLimitExceededError):
            extract_snapshot(snapshot, ocr_provider=CountingProvider())
        assert seen == []


def test_default_http_timeout_is_fifteen_seconds(monkeypatch):
    monkeypatch.setattr("engine.extraction.url_security.socket.getaddrinfo", public_dns)
    timeouts = []
    transport = mock_source_client(b"<p>Nothing relevant</p>")

    def client_factory(*, timeout):
        timeouts.append(timeout)
        return transport

    monkeypatch.setattr(native.httpx, "Client", client_factory)
    fetch_url_snapshot(url_request().url, context=source_context())
    assert timeouts == [15.0]
    assert transport.is_closed


def test_tesseract_process_timeout_keeps_ocr_timeout_identity(monkeypatch):
    provider = TesseractOCRProvider()
    timeouts = []

    def timeout(command, **kwargs):
        timeouts.append(kwargs["timeout"])
        raise subprocess.TimeoutExpired(command, kwargs["timeout"], output=PRIVATE_SENTINEL)

    monkeypatch.setattr(tesseract.subprocess, "run", timeout)
    snapshot = create_pdf_snapshot("timeout.pdf", pdf_bytes(), context=source_context())
    with pytest.raises(OCRTimeoutError):
        extract_snapshot(snapshot, ocr_provider=provider)
    assert timeouts == [20.0]


@pytest.mark.parametrize("late_seconds", [20.0, 21.0, 120.0, 121.0])
def test_last_ocr_page_cannot_return_success_after_page_or_total_budget(monkeypatch, late_seconds):
    now = [0.0]

    class LateProvider(EmptyOCR):
        def extract_page(self, image_bytes, *, page_number, timeout_seconds):
            assert 0 < timeout_seconds <= 20.0
            now[0] = late_seconds
            return ()

    snapshot = create_pdf_snapshot("late.pdf", pdf_bytes(image_only=True), context=source_context())
    monkeypatch.setattr(ocr_service, "monotonic", lambda: now[0])
    with pytest.raises(OCRTimeoutError):
        extract_snapshot(snapshot, ocr_provider=LateProvider())


def test_ocr_remaining_total_budget_clamps_later_page_timeout(monkeypatch):
    now = [0.0]
    timeouts = []

    class SlowProvider(EmptyOCR):
        def extract_page(self, image_bytes, *, page_number, timeout_seconds):
            timeouts.append(timeout_seconds)
            now[0] += 19.0
            return ()

    snapshot = create_pdf_snapshot("slow.pdf", pdf_bytes(pages=7), context=source_context())
    monkeypatch.setattr(ocr_service, "monotonic", lambda: now[0])
    with pytest.raises(OCRTimeoutError):
        extract_snapshot(snapshot, ocr_provider=SlowProvider())
    assert timeouts == [20.0] * 6 + [6.0]


def test_successful_empty_ocr_just_inside_budget_is_still_success(monkeypatch):
    now = [0.0]

    class TimelyProvider(EmptyOCR):
        def extract_page(self, image_bytes, *, page_number, timeout_seconds):
            now[0] = 19.999
            return ()

    snapshot = create_pdf_snapshot("timely.pdf", pdf_bytes(), context=source_context())
    monkeypatch.setattr(ocr_service, "monotonic", lambda: now[0])
    result = extract_snapshot(snapshot, ocr_provider=TimelyProvider())
    assert result.ocr_document.blocks == ()
    assert result.ocr_document.pages_without_ocr_text == (1,)
