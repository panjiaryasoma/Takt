from __future__ import annotations

from datetime import UTC, datetime, timedelta, timezone
from hashlib import sha256

import httpx
import pymupdf
import pytest

from engine.extraction import (
    HttpRetrievalMetadata,
    InvalidSourceError,
    NativeDocument,
    NativeTextBlock,
    OCRDocument,
    OCRExtractionError,
    OCRTextBlock,
    RetrievalMetadata,
    SnapshotBatchError,
    SnapshotExtractionResult,
    SnapshotIntegrityError,
    SourceContext,
    SourceSnapshot,
    UnsupportedMediaTypeError,
    UploadedDocumentMetadata,
    create_pdf_snapshot,
    derive_snapshot_source_ids,
    extract_ocr_snapshot,
    extract_snapshot,
    fetch_url_snapshot,
    ingest_url_native,
    normalize_candidate_report,
    validate_snapshot_extraction_result,
)
from packages.contracts import ExtractionPath, SourceRecord, SourceType

FIXED_TIME = datetime(2026, 9, 24, 8, 0, tzinfo=UTC)


def _context(
    source_id: str = "src-a",
    *,
    scope=None,
    authority_rank=None,
    freshness_metadata=None,
) -> SourceContext:
    return SourceContext(
        source_id=source_id,
        source_type=SourceType.DERIVED_FIXTURE,
        authority_rank=authority_rank or {"kind": "fixture"},
        scope=scope or {"category": "all"},
        freshness_metadata=freshness_metadata or {"fixture_version": 1},
    )


def _pdf_bytes(text: str = "Submission deadline September 30 2026 23 59 WIB") -> bytes:
    document = pymupdf.open()
    page = document.new_page()
    page.insert_text((72, 72), text)
    payload = document.tobytes()
    document.close()
    return payload


class StubOCRProvider:
    provider_id = "stub-ocr"
    provider_version = "stub-1"

    def __init__(
        self,
        *,
        text: str = "Submission deadline September 30 2026 23 59 WIB",
        language: str = "eng",
        page_segmentation_mode: int = 6,
    ) -> None:
        self.text = text
        self.language = language
        self.page_segmentation_mode = page_segmentation_mode
        self.pages_seen: list[int] = []

    def extract_page(
        self,
        image_bytes: bytes,
        *,
        page_number: int,
        timeout_seconds: float,
    ) -> tuple[OCRTextBlock, ...]:
        assert image_bytes.startswith(b"\x89PNG")
        assert timeout_seconds > 0
        self.pages_seen.append(page_number)
        return (
            OCRTextBlock(
                locator=f"page:{page_number}:ocr:block:1:par:1:line:1",
                text=self.text,
                page_number=page_number,
                confidence=0.95,
                bounding_box=(10, 20, 400, 60),
            ),
        )


class FailingOCRProvider(StubOCRProvider):
    def extract_page(self, *args, **kwargs):
        raise OCRExtractionError("provider exploded")


def _source_record(
    *,
    source_id: str = "src-a",
    content: bytes = b"abc",
    scope=None,
) -> SourceRecord:
    return SourceRecord(
        source_id=source_id,
        source_type=SourceType.DERIVED_FIXTURE,
        url_or_document_id="fixture/source.pdf",
        retrieved_at=FIXED_TIME,
        content_hash=f"sha256:{sha256(content).hexdigest()}",
        authority_rank={"kind": "fixture"},
        scope=scope or {"category": "all"},
        freshness_metadata={"fixture_version": 1},
    )


def test_uploaded_pdf_fans_out_same_bytes_to_native_and_ocr() -> None:
    pdf = _pdf_bytes()
    snapshot = create_pdf_snapshot(
        "upload/rules.pdf",
        pdf,
        context=_context(),
        retrieved_at=FIXED_TIME,
    )
    provider = StubOCRProvider()

    result = extract_snapshot(snapshot, ocr_provider=provider)

    assert provider.pages_seen == [1]
    assert result.native_document.source_record.content_hash == (
        result.ocr_document.source_record.content_hash
    )
    assert result.native_document.source_record.content_hash == (
        snapshot.source_record.content_hash
    )
    assert result.native_document.source_record.retrieved_at == (
        result.ocr_document.source_record.retrieved_at
    )
    assert len(result.candidate_reports) == 2
    assert {report.extraction_path for report in result.candidate_reports} == {
        ExtractionPath.NATIVE,
        ExtractionPath.OCR,
    }


def test_source_records_are_materially_equal_but_deep_independent() -> None:
    pdf = _pdf_bytes()
    snapshot = create_pdf_snapshot(
        "upload/rules.pdf",
        pdf,
        context=_context(scope={"category": "all"}),
        retrieved_at=FIXED_TIME,
    )
    result = extract_snapshot(snapshot, ocr_provider=StubOCRProvider())
    native_record = result.native_document.source_record
    ocr_record = result.ocr_document.source_record

    expected = snapshot.source_record.model_dump(mode="python")
    assert native_record.model_dump(mode="python") == expected
    assert ocr_record.model_dump(mode="python") == expected
    assert native_record is not ocr_record

    native_record.scope["category"] = "student"
    assert ocr_record.scope["category"] == "all"
    assert snapshot.source_record.scope["category"] == "all"

    ocr_record.scope["category"] = "professional"
    assert native_record.scope["category"] == "student"
    assert snapshot.source_record.scope["category"] == "all"


def test_mutating_original_source_record_does_not_change_snapshot() -> None:
    content = b"abc"
    source_record = _source_record(content=content)
    metadata = UploadedDocumentMetadata(
        document_id="fixture/source.pdf",
        uploaded_at=FIXED_TIME,
        declared_media_type="application/pdf",
    )
    snapshot = SourceSnapshot(
        source_record=source_record,
        media_type="application/pdf",
        content=content,
        origin_metadata=metadata,
    )
    source_record.scope["category"] = "student"
    assert snapshot.source_record.scope["category"] == "all"


def test_snapshot_id_is_deterministic_for_same_retrieval_material() -> None:
    pdf = _pdf_bytes()
    first = create_pdf_snapshot(
        "upload/rules.pdf",
        pdf,
        context=_context(),
        retrieved_at=FIXED_TIME,
    )
    second = create_pdf_snapshot(
        "upload/rules.pdf",
        pdf,
        context=_context(),
        retrieved_at=FIXED_TIME,
    )
    assert first.snapshot_id == second.snapshot_id


def test_snapshot_id_changes_for_content_or_retrieval_time() -> None:
    first = create_pdf_snapshot(
        "upload/rules.pdf",
        _pdf_bytes("Team size 1 to 4 members"),
        context=_context(),
        retrieved_at=FIXED_TIME,
    )
    changed_content = create_pdf_snapshot(
        "upload/rules.pdf",
        _pdf_bytes("Team size 1 to 5 members"),
        context=_context(),
        retrieved_at=FIXED_TIME,
    )
    changed_time = create_pdf_snapshot(
        "upload/rules.pdf",
        first.content,
        context=_context(),
        retrieved_at=FIXED_TIME + timedelta(seconds=1),
    )
    assert first.snapshot_id != changed_content.snapshot_id
    assert first.snapshot_id != changed_time.snapshot_id


def test_interpretation_metadata_alone_does_not_change_snapshot_id() -> None:
    pdf = _pdf_bytes()
    first = create_pdf_snapshot(
        "upload/rules.pdf",
        pdf,
        context=_context(
            scope={"category": "all"},
            authority_rank={"kind": "fixture", "tier": 1},
            freshness_metadata={"fixture_version": 1},
        ),
        retrieved_at=FIXED_TIME,
    )
    second = create_pdf_snapshot(
        "upload/rules.pdf",
        pdf,
        context=_context(
            scope={"category": "student"},
            authority_rank={"kind": "fixture", "tier": 999},
            freshness_metadata={"fixture_version": 2},
        ),
        retrieved_at=FIXED_TIME,
    )
    assert first.snapshot_id == second.snapshot_id


def test_snapshot_integrity_mismatch_is_rejected_at_construction() -> None:
    source_record = _source_record(content=b"original")
    with pytest.raises(SnapshotIntegrityError):
        SourceSnapshot(
            source_record=source_record,
            media_type="application/pdf",
            content=b"tampered",
            origin_metadata=UploadedDocumentMetadata(
                document_id="fixture/source.pdf",
                uploaded_at=FIXED_TIME,
                declared_media_type="application/pdf",
            ),
        )


def test_http_snapshot_preserves_declared_charset(monkeypatch: pytest.MonkeyPatch) -> None:
    html = "<html><body><p>Harga café</p></body></html>".encode("windows-1252")

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html; charset=windows-1252"},
            content=html,
            request=request,
        )

    monkeypatch.setattr(
        "engine.extraction.native.validate_public_http_target",
        lambda _url: None,
    )
    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        snapshot = fetch_url_snapshot(
            "https://example.test/rules",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    assert isinstance(snapshot.origin_metadata, HttpRetrievalMetadata)
    assert snapshot.origin_metadata.declared_charset == "windows-1252"
    result = extract_snapshot(snapshot)
    assert "Harga café" in result.native_document.text
    assert result.ocr_document is None


def test_fetch_once_means_one_transaction_with_redirect_hops(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    pdf = _pdf_bytes()
    requests: list[str] = []
    security_targets: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(str(request.url))
        if request.url.path == "/rules":
            return httpx.Response(
                302,
                headers={"location": "/rules.pdf"},
                request=request,
            )
        return httpx.Response(
            200,
            headers={"content-type": "application/pdf"},
            content=pdf,
            request=request,
        )

    monkeypatch.setattr(
        "engine.extraction.native.validate_public_http_target",
        lambda url: security_targets.append(url),
    )
    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        snapshot = fetch_url_snapshot(
            "https://example.test/rules",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )
    assert len(requests) == 2
    assert security_targets == [
        "https://example.test/rules",
        "https://example.test/rules.pdf",
    ]

    extract_snapshot(snapshot, ocr_provider=StubOCRProvider())
    assert len(requests) == 2


def test_uploaded_snapshot_uses_upload_metadata_not_fake_http() -> None:
    snapshot = create_pdf_snapshot(
        "upload/rules.pdf",
        _pdf_bytes(),
        context=_context(),
        retrieved_at=FIXED_TIME,
    )
    assert isinstance(snapshot.origin_metadata, UploadedDocumentMetadata)
    assert snapshot.origin_metadata.document_id == "upload/rules.pdf"


def test_direct_ocr_request_against_html_snapshot_is_rejected(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    html = b"<html><body>rules</body></html>"

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
        snapshot = fetch_url_snapshot(
            "https://example.test/rules",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )
    with pytest.raises(Exception, match="requires application/pdf"):
        extract_ocr_snapshot(snapshot, provider=StubOCRProvider())


def test_ocr_failure_propagates_instead_of_becoming_empty_report() -> None:
    snapshot = create_pdf_snapshot(
        "upload/rules.pdf",
        _pdf_bytes(),
        context=_context(),
        retrieved_at=FIXED_TIME,
    )
    with pytest.raises(OCRExtractionError, match="provider exploded"):
        extract_snapshot(snapshot, ocr_provider=FailingOCRProvider())


def test_successful_empty_reports_are_preserved() -> None:
    snapshot = create_pdf_snapshot(
        "upload/rules.pdf",
        _pdf_bytes("Nothing relevant here"),
        context=_context(),
        retrieved_at=FIXED_TIME,
    )
    result = extract_snapshot(
        snapshot,
        ocr_provider=StubOCRProvider(text="Nothing relevant here either"),
    )
    assert len(result.candidate_reports) == 2
    assert all(report.fields == [] for report in result.candidate_reports)


def test_derive_snapshot_source_ids_is_unique_sorted() -> None:
    first = extract_snapshot(
        create_pdf_snapshot(
            "upload/a.pdf",
            _pdf_bytes(),
            context=_context("src-b"),
            retrieved_at=FIXED_TIME,
        ),
        ocr_provider=StubOCRProvider(),
    )
    second = extract_snapshot(
        create_pdf_snapshot(
            "upload/b.pdf",
            _pdf_bytes(),
            context=_context("src-a"),
            retrieved_at=FIXED_TIME,
        ),
        ocr_provider=StubOCRProvider(),
    )
    assert derive_snapshot_source_ids([first, second]) == ("src-a", "src-b")


def test_zero_snapshot_results_are_rejected() -> None:
    with pytest.raises(SnapshotBatchError):
        derive_snapshot_source_ids([])


def test_two_active_snapshots_for_same_source_are_rejected() -> None:
    first = extract_snapshot(
        create_pdf_snapshot(
            "upload/a.pdf",
            _pdf_bytes("Team size 1 to 4 members"),
            context=_context("src-a"),
            retrieved_at=FIXED_TIME,
        ),
        ocr_provider=StubOCRProvider(),
    )
    second = extract_snapshot(
        create_pdf_snapshot(
            "upload/a.pdf",
            _pdf_bytes("Team size 1 to 5 members"),
            context=_context("src-a"),
            retrieved_at=FIXED_TIME + timedelta(seconds=1),
        ),
        ocr_provider=StubOCRProvider(),
    )
    with pytest.raises(SnapshotBatchError, match="multiple active snapshots"):
        derive_snapshot_source_ids([first, second])


def test_candidate_report_source_mismatch_is_rejected_at_handoff() -> None:
    result = extract_snapshot(
        create_pdf_snapshot(
            "upload/a.pdf",
            _pdf_bytes(),
            context=_context("src-a"),
            retrieved_at=FIXED_TIME,
        ),
        ocr_provider=StubOCRProvider(),
    )
    result.candidate_reports[0].source_id = "src-other"
    with pytest.raises(SnapshotBatchError, match="owning snapshot"):
        derive_snapshot_source_ids([result])


def test_evidence_id_is_stable_for_identical_input() -> None:
    record = _source_record(content=b"same")
    doc = NativeDocument(
        source_record=record,
        media_type="text/html",
        raw_size_bytes=4,
        blocks=(
            NativeTextBlock(
                locator="p[1]",
                text="Team size 1 to 4 members",
                kind="p",
            ),
        ),
        parser_version="native-html-v1",
    )
    first = normalize_candidate_report(doc)
    second = normalize_candidate_report(doc)
    assert first.evidence[0].evidence_id == second.evidence[0].evidence_id


def test_evidence_id_changes_when_content_hash_changes() -> None:
    first_record = _source_record(content=b"snapshot-a")
    second_record = _source_record(content=b"snapshot-b")
    block = NativeTextBlock(
        locator="p[1]",
        text="Team size 1 to 4 members",
        kind="p",
    )
    first = normalize_candidate_report(
        NativeDocument(
            source_record=first_record,
            media_type="text/html",
            raw_size_bytes=10,
            blocks=(block,),
            parser_version="native-html-v1",
        )
    )
    second = normalize_candidate_report(
        NativeDocument(
            source_record=second_record,
            media_type="text/html",
            raw_size_bytes=10,
            blocks=(block,),
            parser_version="native-html-v1",
        )
    )
    assert first.evidence[0].evidence_id != second.evidence[0].evidence_id


def test_evidence_id_changes_with_ocr_configuration() -> None:
    record = _source_record(content=b"same")
    block = OCRTextBlock(
        locator="page:1:ocr:block:1:par:1:line:1",
        text="Team size 1 to 4 members",
        page_number=1,
        confidence=0.9,
    )
    first = normalize_candidate_report(
        OCRDocument(
            source_record=record,
            provider_id="stub",
            provider_version="1",
            blocks=(block,),
            page_count=1,
            render_dpi=150,
            extractor_fingerprint="ocr-xfp-config-a",
        )
    )
    second = normalize_candidate_report(
        OCRDocument(
            source_record=record,
            provider_id="stub",
            provider_version="1",
            blocks=(block,),
            page_count=1,
            render_dpi=300,
            extractor_fingerprint="ocr-xfp-config-b",
        )
    )
    assert first.evidence[0].evidence_id != second.evidence[0].evidence_id


def test_evidence_id_changes_when_raw_evidence_changes() -> None:
    record = _source_record(content=b"same")
    first_doc = OCRDocument(
        source_record=record,
        provider_id="stub",
        provider_version="1",
        blocks=(
            OCRTextBlock(
                locator="page:1:ocr:block:1:par:1:line:1",
                text="Team size 1 to 4 members",
                page_number=1,
                confidence=0.9,
            ),
        ),
        page_count=1,
        extractor_fingerprint="ocr-xfp-same-config",
    )
    second_doc = OCRDocument(
        source_record=record,
        provider_id="stub",
        provider_version="1",
        blocks=(
            OCRTextBlock(
                locator="page:1:ocr:block:1:par:1:line:1",
                text="Team size 1  to 4 members",
                page_number=1,
                confidence=0.9,
            ),
        ),
        page_count=1,
        extractor_fingerprint="ocr-xfp-same-config",
    )
    first = normalize_candidate_report(first_doc)
    second = normalize_candidate_report(second_doc)
    assert first.evidence[0].evidence_id != second.evidence[0].evidence_id


def test_native_and_ocr_evidence_ids_do_not_collide_for_same_source() -> None:
    snapshot = create_pdf_snapshot(
        "upload/rules.pdf",
        _pdf_bytes(),
        context=_context(),
        retrieved_at=FIXED_TIME,
    )
    result = extract_snapshot(snapshot, ocr_provider=StubOCRProvider())
    native_ids = {item.evidence_id for item in result.candidate_reports[0].evidence}
    ocr_ids = {item.evidence_id for item in result.candidate_reports[1].evidence}
    assert native_ids
    assert ocr_ids
    assert native_ids.isdisjoint(ocr_ids)



def test_pdf_result_without_ocr_is_rejected_at_handoff() -> None:
    valid = extract_snapshot(
        create_pdf_snapshot(
            "upload/a.pdf",
            _pdf_bytes(),
            context=_context(),
            retrieved_at=FIXED_TIME,
        ),
        ocr_provider=StubOCRProvider(),
    )
    malformed = SnapshotExtractionResult(
        snapshot=valid.snapshot,
        native_document=valid.native_document,
        ocr_document=None,
        bound_candidate_reports=(valid.bound_candidate_reports[0],),
    )
    with pytest.raises(SnapshotBatchError, match="requires an OCRDocument"):
        derive_snapshot_source_ids([malformed])


def test_html_result_with_ocr_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    html = b"<html><body>Team size 1 to 4 members</body></html>"

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
        html_result = extract_snapshot(
            fetch_url_snapshot(
                "https://example.test/rules",
                context=_context(),
                client=client,
                retrieved_at=FIXED_TIME,
            )
        )
    pdf_result = extract_snapshot(
        create_pdf_snapshot(
            "upload/a.pdf",
            _pdf_bytes(),
            context=_context(),
            retrieved_at=FIXED_TIME,
        ),
        ocr_provider=StubOCRProvider(),
    )
    malformed = SnapshotExtractionResult(
        snapshot=html_result.snapshot,
        native_document=html_result.native_document,
        ocr_document=pdf_result.ocr_document,
        bound_candidate_reports=html_result.bound_candidate_reports,
    )
    with pytest.raises(SnapshotBatchError, match="must not contain an OCR"):
        validate_snapshot_extraction_result(malformed)


def test_mutated_native_source_material_is_rejected() -> None:
    result = extract_snapshot(
        create_pdf_snapshot(
            "upload/a.pdf",
            _pdf_bytes(),
            context=_context(),
            retrieved_at=FIXED_TIME,
        ),
        ocr_provider=StubOCRProvider(),
    )
    result.native_document.source_record.content_hash = "sha256:" + ("0" * 64)
    with pytest.raises(SnapshotBatchError, match="SourceRecord"):
        derive_snapshot_source_ids([result])


def test_mutated_native_raw_size_is_rejected() -> None:
    result = extract_snapshot(
        create_pdf_snapshot(
            "upload/a.pdf",
            _pdf_bytes(),
            context=_context(),
            retrieved_at=FIXED_TIME,
        ),
        ocr_provider=StubOCRProvider(),
    )
    object.__setattr__(result.native_document, "raw_size_bytes", 1)
    with pytest.raises(SnapshotBatchError, match="raw_size_bytes"):
        derive_snapshot_source_ids([result])


def test_candidate_report_from_another_snapshot_is_rejected() -> None:
    first = extract_snapshot(
        create_pdf_snapshot(
            "upload/a.pdf",
            _pdf_bytes("Team size 1 to 4 members"),
            context=_context(),
            retrieved_at=FIXED_TIME,
        ),
        ocr_provider=StubOCRProvider(text="Team size 1 to 4 members"),
    )
    second = extract_snapshot(
        create_pdf_snapshot(
            "upload/a.pdf",
            _pdf_bytes("Team size 1 to 5 members"),
            context=_context(),
            retrieved_at=FIXED_TIME + timedelta(seconds=1),
        ),
        ocr_provider=StubOCRProvider(text="Team size 1 to 5 members"),
    )
    malformed = SnapshotExtractionResult(
        snapshot=first.snapshot,
        native_document=first.native_document,
        ocr_document=first.ocr_document,
        bound_candidate_reports=(
            second.bound_candidate_reports[0],
            first.bound_candidate_reports[1],
        ),
    )
    with pytest.raises(SnapshotBatchError):
        derive_snapshot_source_ids([malformed])


def test_foreign_empty_candidate_report_binding_is_rejected() -> None:
    first = extract_snapshot(
        create_pdf_snapshot(
            "upload/a.pdf",
            _pdf_bytes("No supported labeled field here"),
            context=_context(),
            retrieved_at=FIXED_TIME,
        ),
        ocr_provider=StubOCRProvider(text="No supported labeled field here"),
    )
    second = extract_snapshot(
        create_pdf_snapshot(
            "upload/a.pdf",
            _pdf_bytes("Still no supported labeled field"),
            context=_context(),
            retrieved_at=FIXED_TIME + timedelta(seconds=1),
        ),
        ocr_provider=StubOCRProvider(text="Still no supported labeled field"),
    )

    assert second.candidate_reports[0].fields == []
    assert second.candidate_reports[0].evidence == []

    malformed = SnapshotExtractionResult(
        snapshot=first.snapshot,
        native_document=first.native_document,
        ocr_document=first.ocr_document,
        bound_candidate_reports=(
            second.bound_candidate_reports[0],
            first.bound_candidate_reports[1],
        ),
    )

    with pytest.raises(SnapshotBatchError, match="snapshot_id"):
        derive_snapshot_source_ids([malformed])


def test_mutated_candidate_report_path_is_rejected() -> None:
    result = extract_snapshot(
        create_pdf_snapshot(
            "upload/a.pdf",
            _pdf_bytes(),
            context=_context(),
            retrieved_at=FIXED_TIME,
        ),
        ocr_provider=StubOCRProvider(),
    )
    result.candidate_reports[0].extraction_path = ExtractionPath.OCR
    with pytest.raises(SnapshotBatchError):
        derive_snapshot_source_ids([result])


def test_unsupported_snapshot_media_is_rejected() -> None:
    content = b"abc"
    record = _source_record(content=content)
    with pytest.raises(UnsupportedMediaTypeError):
        SourceSnapshot(
            source_record=record,
            media_type="application/banana",
            content=content,
            origin_metadata=UploadedDocumentMetadata(
                document_id="fixture/source.pdf",
                uploaded_at=FIXED_TIME,
                declared_media_type="application/banana",
            ),
        )


def test_uploaded_snapshot_document_id_mismatch_is_rejected() -> None:
    content = b"abc"
    record = _source_record(content=content)
    with pytest.raises(InvalidSourceError, match="document_id"):
        SourceSnapshot(
            source_record=record,
            media_type="application/pdf",
            content=content,
            origin_metadata=UploadedDocumentMetadata(
                document_id="different.pdf",
                uploaded_at=FIXED_TIME,
                declared_media_type="application/pdf",
            ),
        )


def test_uploaded_snapshot_timestamp_mismatch_is_rejected() -> None:
    content = b"abc"
    record = _source_record(content=content)
    with pytest.raises(InvalidSourceError, match="timestamp"):
        SourceSnapshot(
            source_record=record,
            media_type="application/pdf",
            content=content,
            origin_metadata=UploadedDocumentMetadata(
                document_id="fixture/source.pdf",
                uploaded_at=FIXED_TIME + timedelta(seconds=1),
                declared_media_type="application/pdf",
            ),
        )


def test_http_snapshot_resolved_url_mismatch_is_rejected() -> None:
    content = b"<html></html>"
    record = SourceRecord(
        source_id="src-a",
        source_type=SourceType.DERIVED_FIXTURE,
        url_or_document_id="https://example.test/final",
        retrieved_at=FIXED_TIME,
        content_hash=f"sha256:{sha256(content).hexdigest()}",
        authority_rank={"kind": "fixture"},
        scope={"category": "all"},
        freshness_metadata={"fixture_version": 1},
    )
    with pytest.raises(InvalidSourceError, match="resolved_url"):
        SourceSnapshot(
            source_record=record,
            media_type="text/html",
            content=content,
            origin_metadata=HttpRetrievalMetadata(
                requested_url="https://example.test/start",
                resolved_url="https://example.test/other",
                status_code=200,
                content_type="text/html",
            ),
        )


def test_redirect_chain_input_is_deep_owned_and_canonical_tuple() -> None:
    content = b"<html></html>"
    chain = ["https://example.test/start"]
    metadata = RetrievalMetadata(
        requested_url="https://example.test/start",
        resolved_url="https://example.test/final",
        status_code=200,
        content_type="text/html",
        etag=None,
        last_modified=None,
        redirect_chain=chain,
    )
    record = SourceRecord(
        source_id="src-a",
        source_type=SourceType.DERIVED_FIXTURE,
        url_or_document_id="https://example.test/final",
        retrieved_at=FIXED_TIME,
        content_hash=f"sha256:{sha256(content).hexdigest()}",
        authority_rank={"kind": "fixture"},
        scope={"category": "all"},
        freshness_metadata={"fixture_version": 1},
    )
    snapshot = SourceSnapshot(
        source_record=record,
        media_type="text/html",
        content=content,
        origin_metadata=metadata,
    )
    chain.append("https://mutated.test")
    assert snapshot.origin_metadata.redirect_chain == (
        "https://example.test/start",
    )


def test_retrieval_metadata_old_content_type_constructor_still_works() -> None:
    metadata = RetrievalMetadata(
        requested_url="https://example.test/start",
        resolved_url="https://example.test/final",
        status_code=200,
        content_type="text/html",
        etag=None,
        last_modified=None,
    )
    assert metadata.content_type == "text/html"
    assert metadata.declared_content_type == "text/html"


def test_snapshot_id_canonicalizes_same_instant_to_utc() -> None:
    pdf = _pdf_bytes()
    utc_snapshot = create_pdf_snapshot(
        "upload/a.pdf",
        pdf,
        context=_context(),
        retrieved_at=FIXED_TIME,
    )
    plus_seven = FIXED_TIME.astimezone(timezone(timedelta(hours=7)))
    local_snapshot = create_pdf_snapshot(
        "upload/a.pdf",
        pdf,
        context=_context(),
        retrieved_at=plus_seven,
    )
    assert utc_snapshot.snapshot_id == local_snapshot.snapshot_id


def test_ingest_url_native_invalid_native_limit_does_not_fetch(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    request_count = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal request_count
        request_count += 1
        return httpx.Response(
            200,
            headers={"content-type": "text/html"},
            content=b"<html></html>",
            request=request,
        )

    monkeypatch.setattr(
        "engine.extraction.native.validate_public_http_target",
        lambda _url: None,
    )
    with (
        httpx.Client(transport=httpx.MockTransport(handler)) as client,
        pytest.raises(
            InvalidSourceError,
            match="native extraction limits",
        ),
    ):
        ingest_url_native(
            "https://example.test/rules",
            context=_context(),
            client=client,
            max_native_blocks=0,
        )
    assert request_count == 0


def test_duplicate_snapshot_extraction_result_is_rejected() -> None:
    result = extract_snapshot(
        create_pdf_snapshot(
            "upload/a.pdf",
            _pdf_bytes(),
            context=_context(),
            retrieved_at=FIXED_TIME,
        ),
        ocr_provider=StubOCRProvider(),
    )
    with pytest.raises(SnapshotBatchError, match="exactly one"):
        derive_snapshot_source_ids([result, result])
