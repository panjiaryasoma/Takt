from __future__ import annotations

import shutil
import subprocess
from datetime import UTC, datetime
from hashlib import sha256
from pathlib import Path

import pymupdf
import pytest

from engine.extraction import (
    CandidateNormalizationError,
    NativeDocument,
    OCRDocument,
    OCRExtractionError,
    OCRProviderUnavailableError,
    OCRTextBlock,
    OCRTimeoutError,
    SourceLimitExceededError,
    TesseractOCRProvider,
    ingest_pdf_native,
    normalize_candidate_report,
    ocr_pdf,
)
from packages.contracts import SourceRecord, SourceType

FIXTURES = Path(__file__).parents[1] / "fixtures" / "extraction"
FIXED_TIME = datetime(2026, 9, 24, 1, 0, tzinfo=UTC)


def _source_record(
    source_id: str = "src-ocr-001",
    *,
    content: bytes | None = None,
    content_hash: str | None = None,
) -> SourceRecord:
    if content is None:
        content = (FIXTURES / "ocr_competition.pdf").read_bytes()
    if content_hash is None:
        content_hash = f"sha256:{sha256(content).hexdigest()}"
    return SourceRecord(
        source_id=source_id,
        source_type=SourceType.DERIVED_FIXTURE,
        url_or_document_id="fixture/ocr_competition.pdf",
        retrieved_at=FIXED_TIME,
        content_hash=content_hash,
        authority_rank={"kind": "fixture"},
        scope={"competition": "fixture"},
        freshness_metadata={"fixture_version": 1},
    )


class StubSemanticOCRProvider:
    provider_id = "stub-semantic-ocr"
    provider_version = "stub-semantic-1"

    def extract_page(
        self,
        image_bytes: bytes,
        *,
        page_number: int,
        timeout_seconds: float,
    ) -> tuple[OCRTextBlock, ...]:
        assert image_bytes.startswith(b"\x89PNG")
        assert timeout_seconds > 0
        if page_number == 1:
            return (
                OCRTextBlock(
                    locator="page:1:ocr:block:1:par:1:line:2",
                    text="Submission deadline September 30 2026 23 59 WIB",
                    page_number=1,
                    confidence=0.95,
                    bounding_box=(10, 20, 400, 60),
                ),
            )
        return (
            OCRTextBlock(
                locator="page:2:ocr:block:1:par:1:line:1",
                text="Team size 1 to 4 members",
                page_number=2,
                confidence=0.96,
                bounding_box=(10, 20, 300, 60),
            ),
        )


class StubOCRProvider:
    provider_id = "stub-ocr"
    provider_version = "stub-1"

    def __init__(self) -> None:
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
                text=f"ocr page {page_number}",
                page_number=page_number,
                confidence=0.9,
                bounding_box=(10, 20, 200, 60),
            ),
        )


def test_ocr_provider_is_replaceable_and_runs_independently_on_native_pdf() -> None:
    pdf = (FIXTURES / "native_competition.pdf").read_bytes()
    source_record = _source_record(content=pdf)
    provider = StubOCRProvider()

    native = ingest_pdf_native(
        "fixture/native_competition.pdf",
        pdf,
        context=_native_context(),
        retrieved_at=FIXED_TIME,
    )
    assert isinstance(native, NativeDocument)
    assert native.has_native_text is True

    result = ocr_pdf(pdf, source_record=source_record, provider=provider)

    assert isinstance(result, OCRDocument)
    assert provider.pages_seen == [1, 2]
    assert result.provider_id == "stub-ocr"
    assert result.provider_version == "stub-1"
    assert result.text == "ocr page 1\nocr page 2"


def _native_context():
    from engine.extraction import SourceContext

    return SourceContext(
        source_id="src-native-peer",
        source_type=SourceType.DERIVED_FIXTURE,
        authority_rank={"kind": "fixture"},
        scope={"competition": "fixture"},
        freshness_metadata={"fixture_version": 1},
    )


@pytest.mark.skipif(shutil.which("tesseract") is None, reason="Tesseract CLI is not installed")
def test_image_only_pdf_fixture_is_read_by_real_tesseract_provider() -> None:
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()
    source_record = _source_record()

    native = ingest_pdf_native(
        "fixture/ocr_competition.pdf",
        pdf,
        context=_native_context(),
        retrieved_at=FIXED_TIME,
    )
    assert native.has_native_text is False
    assert native.pages_without_native_text == (1, 2)

    provider = TesseractOCRProvider()
    result = ocr_pdf(pdf, source_record=source_record, provider=provider)

    assert result.page_count == 2
    assert result.pages_without_ocr_text == ()
    assert result.provider_id == "tesseract"
    assert "tesseract" in result.provider_version.lower()
    assert "Takt OCR Fixture Hackathon" in result.text
    assert "Submission deadline September 30 2026" in result.text
    assert "Team size 1 to 4 members" in result.text
    assert all(block.bounding_box is not None for block in result.blocks)
    assert all(block.confidence is None or 0 <= block.confidence <= 1 for block in result.blocks)
    assert all(
        block.locator.startswith(f"page:{block.page_number}:ocr:")
        for block in result.blocks
    )


def test_ocr_service_preserves_source_record_identity() -> None:
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()
    source_record = _source_record("src-same-source")
    result = ocr_pdf(pdf, source_record=source_record, provider=StubOCRProvider())

    assert result.source_record is source_record
    assert result.source_record.source_id == "src-same-source"


def test_ocr_corrupt_pdf_uses_explicit_error_boundary() -> None:
    content = b"%PDF-not-a-real-pdf"
    with pytest.raises(OCRExtractionError, match="could not be opened") as caught:
        ocr_pdf(
            content,
            source_record=_source_record(content=content),
            provider=StubOCRProvider(),
        )

    assert caught.value.code == "OCR_EXTRACTION_FAILED"


def test_tesseract_missing_binary_is_explicit_provider_error() -> None:
    with pytest.raises(OCRProviderUnavailableError) as caught:
        TesseractOCRProvider(binary="definitely-not-a-real-tesseract-binary")

    assert caught.value.code == "OCR_PROVIDER_UNAVAILABLE"


def test_tesseract_timeout_is_normalized(monkeypatch: pytest.MonkeyPatch) -> None:
    real_run = subprocess.run
    calls = 0

    def fake_run(*args, **kwargs):
        nonlocal calls
        calls += 1
        if calls == 1:
            return subprocess.CompletedProcess(
                args=args[0],
                returncode=0,
                stdout="tesseract 5.5.0\n",
                stderr="",
            )
        raise subprocess.TimeoutExpired(cmd=args[0], timeout=kwargs["timeout"])

    monkeypatch.setattr("engine.extraction.ocr.tesseract.subprocess.run", fake_run)
    provider = TesseractOCRProvider()

    with pytest.raises(OCRTimeoutError, match="timed out") as caught:
        provider.extract_page(
            b"fake-image",
            page_number=1,
            timeout_seconds=0.1,
        )

    assert caught.value.code == "OCR_TIMEOUT"
    monkeypatch.setattr("engine.extraction.ocr.tesseract.subprocess.run", real_run)


def test_tesseract_tsv_groups_words_into_line_with_bbox_and_confidence() -> None:
    payload = (
        b"level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\t"
        b"left\ttop\twidth\theight\tconf\ttext\n"
        b"5\t1\t1\t1\t1\t1\t10\t20\t30\t10\t90.0\tDeadline\n"
        b"5\t1\t1\t1\t1\t2\t45\t20\t25\t10\t80.0\tSep\n"
        b"5\t1\t1\t1\t1\t3\t75\t20\t20\t10\t70.0\t30\n"
    )

    blocks = TesseractOCRProvider._parse_tsv(payload, page_number=2)

    assert len(blocks) == 1
    assert blocks[0].text == "Deadline Sep 30"
    assert blocks[0].page_number == 2
    assert blocks[0].locator == "page:2:ocr:block:1:par:1:line:1"
    assert blocks[0].bounding_box == (10, 20, 95, 30)
    assert blocks[0].confidence == pytest.approx(0.8)


def test_ocr_source_byte_limit_is_enforced_before_pdf_open() -> None:
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()

    with pytest.raises(SourceLimitExceededError, match="byte limit"):
        ocr_pdf(
            pdf,
            source_record=_source_record(),
            provider=StubOCRProvider(),
            max_source_bytes=32,
        )


def test_ocr_page_limit_is_enforced() -> None:
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()

    with pytest.raises(SourceLimitExceededError, match="page limit"):
        ocr_pdf(
            pdf,
            source_record=_source_record(),
            provider=StubOCRProvider(),
            max_pages=1,
        )


def test_ocr_pixel_limit_is_checked_before_rasterization() -> None:
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()

    with pytest.raises(SourceLimitExceededError, match="pixel limit"):
        ocr_pdf(
            pdf,
            source_record=_source_record(),
            provider=StubOCRProvider(),
            max_image_pixels=100,
        )


class ManyBlockProvider(StubOCRProvider):
    def extract_page(
        self,
        image_bytes: bytes,
        *,
        page_number: int,
        timeout_seconds: float,
    ) -> tuple[OCRTextBlock, ...]:
        return (
            OCRTextBlock(
                locator=f"page:{page_number}:ocr:1",
                text="alpha",
                page_number=page_number,
            ),
            OCRTextBlock(
                locator=f"page:{page_number}:ocr:2",
                text="beta",
                page_number=page_number,
            ),
        )


def test_ocr_block_limit_is_enforced() -> None:
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()

    with pytest.raises(SourceLimitExceededError, match="block limit"):
        ocr_pdf(
            pdf,
            source_record=_source_record(),
            provider=ManyBlockProvider(),
            max_blocks=1,
        )


def test_ocr_text_limit_is_enforced() -> None:
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()

    with pytest.raises(SourceLimitExceededError, match="extracted text limit"):
        ocr_pdf(
            pdf,
            source_record=_source_record(),
            provider=ManyBlockProvider(),
            max_text_chars=3,
        )


class BlankProvider(StubOCRProvider):
    def extract_page(
        self,
        image_bytes: bytes,
        *,
        page_number: int,
        timeout_seconds: float,
    ) -> tuple[OCRTextBlock, ...]:
        return ()


def test_ocr_pages_without_text_are_preserved_as_observability_metadata() -> None:
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()
    result = ocr_pdf(pdf, source_record=_source_record(), provider=BlankProvider())

    assert result.blocks == ()
    assert result.pages_without_ocr_text == (1, 2)
    assert result.has_ocr_text is False


class WrongPageProvider(StubOCRProvider):
    def extract_page(
        self,
        image_bytes: bytes,
        *,
        page_number: int,
        timeout_seconds: float,
    ) -> tuple[OCRTextBlock, ...]:
        return (
            OCRTextBlock(
                locator="wrong-page",
                text="oops",
                page_number=page_number + 1,
            ),
        )


def test_ocr_provider_cannot_return_blocks_for_another_page() -> None:
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()

    with pytest.raises(OCRExtractionError, match="wrong page"):
        ocr_pdf(
            pdf,
            source_record=_source_record(),
            provider=WrongPageProvider(),
        )


def test_invalid_ocr_limits_fail_before_work_starts() -> None:
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()

    with pytest.raises(OCRExtractionError, match="resource limits"):
        ocr_pdf(
            pdf,
            source_record=_source_record(),
            provider=StubOCRProvider(),
            render_dpi=0,
        )


def test_native_and_ocr_share_real_candidate_report_normalizer() -> None:
    from engine.extraction import normalize_candidate_report
    from packages.contracts import CandidateExtractionReport, ExtractionPath

    ocr_pdf_bytes = (FIXTURES / "ocr_competition.pdf").read_bytes()
    ocr_document = ocr_pdf(
        ocr_pdf_bytes,
        source_record=_source_record("src-shared-contract"),
        provider=StubSemanticOCRProvider(),
    )
    ocr_report = normalize_candidate_report(ocr_document)

    native_pdf_bytes = (FIXTURES / "native_competition.pdf").read_bytes()
    native_document = ingest_pdf_native(
        "fixture/native_competition.pdf",
        native_pdf_bytes,
        context=_native_context(),
        retrieved_at=FIXED_TIME,
    )
    native_report = normalize_candidate_report(native_document)

    assert isinstance(ocr_report, CandidateExtractionReport)
    assert isinstance(native_report, CandidateExtractionReport)
    assert ocr_report.extraction_path is ExtractionPath.OCR
    assert native_report.extraction_path is ExtractionPath.NATIVE
    assert {field.field_name for field in ocr_report.fields} == {
        "submission_deadline",
        "team_size",
    }
    assert {field.field_name for field in native_report.fields} == {
        "submission_deadline",
    }


def test_candidate_bridge_rejects_path_mismatch() -> None:
    from engine.extraction import CandidateNormalizationError, normalize_candidate_report
    from packages.contracts import CandidateExtractionReport, ExtractionPath

    class WrongPathNormalizer:
        def normalize(self, document, *, extraction_path):
            return CandidateExtractionReport(
                source_id=document.source_record.source_id,
                extraction_path=ExtractionPath.NATIVE,
                fields=[],
                evidence=[],
            )

    source_record = _source_record("src-path-mismatch")
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()
    ocr_document = ocr_pdf(pdf, source_record=source_record, provider=StubOCRProvider())

    with pytest.raises(CandidateNormalizationError, match="extraction_path"):
        normalize_candidate_report(
            ocr_document,
            normalizer=WrongPathNormalizer(),
        )


class MissingMetadataProvider(StubOCRProvider):
    provider_id = ""


def test_ocr_provider_metadata_must_be_explicit() -> None:
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()

    with pytest.raises(OCRExtractionError, match="provider_id"):
        ocr_pdf(
            pdf,
            source_record=_source_record(),
            provider=MissingMetadataProvider(),
        )


class CrashingProvider(StubOCRProvider):
    def extract_page(
        self,
        image_bytes: bytes,
        *,
        page_number: int,
        timeout_seconds: float,
    ) -> tuple[OCRTextBlock, ...]:
        raise ValueError("provider internals exploded")


def test_raw_provider_exception_is_normalized() -> None:
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()

    with pytest.raises(OCRExtractionError, match="provider failed on page 1"):
        ocr_pdf(
            pdf,
            source_record=_source_record(),
            provider=CrashingProvider(),
        )


class DuplicateLocatorProvider(StubOCRProvider):
    def extract_page(
        self,
        image_bytes: bytes,
        *,
        page_number: int,
        timeout_seconds: float,
    ) -> tuple[OCRTextBlock, ...]:
        locator = "ocr:duplicate"
        return (
            OCRTextBlock(locator=locator, text="alpha", page_number=page_number),
            OCRTextBlock(locator=locator, text="beta", page_number=page_number),
        )


def test_ocr_provider_duplicate_locators_are_rejected() -> None:
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()

    with pytest.raises(OCRExtractionError, match="duplicate locators"):
        ocr_pdf(
            pdf,
            source_record=_source_record(),
            provider=DuplicateLocatorProvider(),
        )


class BadConfidenceProvider(StubOCRProvider):
    def extract_page(
        self,
        image_bytes: bytes,
        *,
        page_number: int,
        timeout_seconds: float,
    ) -> tuple[OCRTextBlock, ...]:
        return (
            OCRTextBlock(
                locator="ocr:bad-confidence",
                text="alpha",
                page_number=page_number,
                confidence=1.5,
            ),
        )


def test_ocr_provider_confidence_outside_zero_to_one_is_rejected() -> None:
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()

    with pytest.raises(OCRExtractionError, match="confidence"):
        ocr_pdf(
            pdf,
            source_record=_source_record(),
            provider=BadConfidenceProvider(),
        )


def test_ocr_total_timeout_budget_is_enforced(monkeypatch: pytest.MonkeyPatch) -> None:
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()
    ticks = iter([0.0, 1.0])
    monkeypatch.setattr(
        "engine.extraction.ocr.service.monotonic",
        lambda: next(ticks),
    )

    with pytest.raises(OCRTimeoutError, match="total timeout"):
        ocr_pdf(
            pdf,
            source_record=_source_record(),
            provider=StubOCRProvider(),
            total_timeout_seconds=0.5,
        )



def test_ocr_rejects_content_hash_mismatch() -> None:
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()
    other = (FIXTURES / "native_competition.pdf").read_bytes()
    source_record = _source_record(content=other)

    with pytest.raises(OCRExtractionError, match="do not match") as caught:
        ocr_pdf(pdf, source_record=source_record, provider=StubOCRProvider())

    assert caught.value.code == "OCR_EXTRACTION_FAILED"


def test_ocr_rejects_unverifiable_source_hash_scheme() -> None:
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()
    source_record = _source_record(content_hash="fixture-hash")

    with pytest.raises(OCRExtractionError, match="cannot be verified") as caught:
        ocr_pdf(pdf, source_record=source_record, provider=StubOCRProvider())

    assert caught.value.code == "OCR_EXTRACTION_FAILED"


def test_encrypted_pdf_is_normalized_to_ocr_extraction_error() -> None:
    document = pymupdf.open()
    page = document.new_page()
    page.insert_text((72, 72), "secret competition rules")
    encrypted = document.tobytes(
        encryption=pymupdf.PDF_ENCRYPT_AES_256,
        owner_pw="owner-password",
        user_pw="user-password",
    )
    document.close()

    with pytest.raises(OCRExtractionError, match="encrypted") as caught:
        ocr_pdf(
            encrypted,
            source_record=_source_record(content=encrypted),
            provider=StubOCRProvider(),
        )

    assert caught.value.code == "OCR_EXTRACTION_FAILED"


class NoneReturningProvider(StubOCRProvider):
    def extract_page(
        self,
        image_bytes: bytes,
        *,
        page_number: int,
        timeout_seconds: float,
    ):
        return None


class ListReturningProvider(StubOCRProvider):
    def extract_page(
        self,
        image_bytes: bytes,
        *,
        page_number: int,
        timeout_seconds: float,
    ):
        return []


@pytest.mark.parametrize(
    "provider",
    [NoneReturningProvider(), ListReturningProvider()],
)
def test_ocr_provider_wrong_return_container_is_rejected(provider) -> None:
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()

    with pytest.raises(OCRExtractionError, match="must return tuple"):
        ocr_pdf(pdf, source_record=_source_record(), provider=provider)


class FalseyProvider(StubOCRProvider):
    provider_id = "falsey-provider"
    provider_version = "falsey-1"

    def __bool__(self) -> bool:
        return False


def test_falsey_custom_provider_is_not_replaced_by_tesseract() -> None:
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()
    provider = FalseyProvider()

    result = ocr_pdf(pdf, source_record=_source_record(), provider=provider)

    assert result.provider_id == "falsey-provider"
    assert provider.pages_seen == [1, 2]


class NoneNormalizer:
    def normalize(self, document, *, extraction_path):
        return None


class CrashingNormalizer:
    def normalize(self, document, *, extraction_path):
        raise ValueError("normalizer internals exploded")


def _semantic_ocr_document() -> OCRDocument:
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()
    return ocr_pdf(
        pdf,
        source_record=_source_record("src-semantic-ocr"),
        provider=StubSemanticOCRProvider(),
    )


def test_candidate_bridge_rejects_invalid_normalizer_return_type() -> None:
    with pytest.raises(CandidateNormalizationError, match="must return") as caught:
        normalize_candidate_report(
            _semantic_ocr_document(),
            normalizer=NoneNormalizer(),
        )

    assert caught.value.code == "CANDIDATE_NORMALIZATION_FAILED"


def test_candidate_bridge_normalizes_raw_normalizer_exception() -> None:
    with pytest.raises(CandidateNormalizationError, match="normalizer failed") as caught:
        normalize_candidate_report(
            _semantic_ocr_document(),
            normalizer=CrashingNormalizer(),
        )

    assert caught.value.code == "CANDIDATE_NORMALIZATION_FAILED"


def test_default_candidate_normalizer_preserves_ocr_locator_and_version() -> None:
    document = _semantic_ocr_document()
    report = normalize_candidate_report(document)

    fields = {field.field_name: field for field in report.fields}
    evidence = {item.field_name: item for item in report.evidence}
    observed = {block.locator: block.text for block in document.blocks}

    assert fields["submission_deadline"].normalized_value == (
        "2026-09-30T23:59:00+07:00"
    )
    assert fields["team_size"].normalized_value == {"min": 1, "max": 4}
    assert fields["submission_deadline"].confidence == pytest.approx(0.95)
    assert fields["team_size"].confidence == pytest.approx(0.96)

    for item in evidence.values():
        assert item.page_or_locator in observed
        assert item.raw_text_or_visual_reference == observed[item.page_or_locator]
        assert document.provider_id in item.extractor_version
        assert document.provider_version in item.extractor_version
        assert "candidate-normalizer:rule-based-v1" in item.extractor_version


@pytest.mark.skipif(shutil.which("tesseract") is None, reason="Tesseract CLI is not installed")
def test_real_tesseract_output_becomes_candidate_extraction_report() -> None:
    pdf = (FIXTURES / "ocr_competition.pdf").read_bytes()
    document = ocr_pdf(
        pdf,
        source_record=_source_record("src-real-candidate"),
        provider=TesseractOCRProvider(),
    )

    report = normalize_candidate_report(document)
    fields = {field.field_name: field for field in report.fields}
    evidence_by_field = {item.field_name: item for item in report.evidence}
    observed = {block.locator: block.text for block in document.blocks}

    assert fields["submission_deadline"].normalized_value == (
        "2026-09-30T23:59:00+07:00"
    )
    assert fields["team_size"].normalized_value == {"min": 1, "max": 4}

    deadline_evidence = evidence_by_field["submission_deadline"]
    team_evidence = evidence_by_field["team_size"]
    for item in (deadline_evidence, team_evidence):
        assert item.page_or_locator in observed
        assert item.raw_text_or_visual_reference == observed[item.page_or_locator]
        assert document.provider_version in item.extractor_version
        assert "candidate-normalizer:rule-based-v1" in item.extractor_version
