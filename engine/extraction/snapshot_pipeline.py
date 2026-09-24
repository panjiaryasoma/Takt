"""Shared SourceSnapshot fan-out for independent native and OCR observations."""

from __future__ import annotations

from collections.abc import Iterable
from typing import Any

from pydantic import ValidationError

from engine.extraction.candidate_bridge import (
    CandidateReportNormalizer,
    normalize_candidate_report,
)
from engine.extraction.candidate_normalizer import build_evidence_id
from engine.extraction.errors import (
    SnapshotBatchError,
    UnsupportedMediaTypeError,
)
from engine.extraction.models import (
    HttpRetrievalMetadata,
    NativeDocument,
    SnapshotBoundCandidateReport,
    SnapshotExtractionResult,
    SourceSnapshot,
    UploadedDocumentMetadata,
)
from engine.extraction.native import extract_native_snapshot, verify_snapshot_integrity
from engine.extraction.ocr import OCRDocument, OCRProvider, ocr_pdf
from packages.contracts import CandidateExtractionReport, ExtractionPath


def extract_ocr_snapshot(
    snapshot: SourceSnapshot,
    *,
    provider: OCRProvider | None = None,
    **ocr_kwargs: Any,
) -> OCRDocument:
    """Run OCR against a PDF snapshot using a deep-independent SourceRecord."""

    if not isinstance(snapshot, SourceSnapshot):
        raise SnapshotBatchError("snapshot must be a SourceSnapshot")
    verify_snapshot_integrity(snapshot)
    if snapshot.media_type != "application/pdf":
        raise UnsupportedMediaTypeError(
            "OCR snapshot extraction requires application/pdf",
            source_ref=snapshot.source_record.url_or_document_id,
        )
    return ocr_pdf(
        snapshot.content,
        source_record=snapshot.source_record,
        provider=provider,
        **ocr_kwargs,
    )


def _source_material(document_source: object) -> dict[str, Any]:
    try:
        return document_source.model_dump(mode="python")
    except (AttributeError, TypeError, ValueError) as exc:
        raise SnapshotBatchError(
            "extraction document must carry a valid SourceRecord"
        ) from exc


def _validate_document_source(
    *,
    snapshot: SourceSnapshot,
    document_source: object,
    path_name: str,
) -> None:
    if _source_material(document_source) != snapshot.source_record_material():
        raise SnapshotBatchError(
            f"{path_name} document SourceRecord must match owning snapshot material",
            source_ref=snapshot.source_record.source_id,
        )


def _validated_report(report: CandidateExtractionReport) -> CandidateExtractionReport:
    if not isinstance(report, CandidateExtractionReport):
        raise SnapshotBatchError(
            "snapshot extraction result must contain CandidateExtractionReport values"
        )
    try:
        return CandidateExtractionReport.model_validate(
            report.model_dump(mode="python")
        )
    except (AttributeError, TypeError, ValueError, ValidationError) as exc:
        raise SnapshotBatchError(
            "candidate report violates extraction contract"
        ) from exc


def _document_blocks(document: NativeDocument | OCRDocument) -> dict[str, str]:
    blocks: dict[str, str] = {}
    for block in document.blocks:
        locator = getattr(block, "locator", None)
        text = getattr(block, "text", None)
        if not isinstance(locator, str) or not isinstance(text, str):
            raise SnapshotBatchError("extraction document contains invalid text blocks")
        if locator in blocks:
            raise SnapshotBatchError("extraction document contains duplicate locators")
        blocks[locator] = text
    return blocks


def _validate_report_against_document(
    *,
    snapshot: SourceSnapshot,
    report: CandidateExtractionReport,
    document: NativeDocument | OCRDocument,
    expected_path: ExtractionPath,
) -> CandidateExtractionReport:
    validated = _validated_report(report)
    source_record = snapshot.source_record

    if validated.source_id != source_record.source_id:
        raise SnapshotBatchError(
            "candidate report source_id must match owning snapshot source_id",
            source_ref=source_record.source_id,
        )
    if validated.extraction_path is not expected_path:
        raise SnapshotBatchError(
            "candidate report extraction_path must match owning document path",
            source_ref=source_record.source_id,
        )

    blocks = _document_blocks(document)
    for evidence in validated.evidence:
        locator = evidence.page_or_locator
        raw_evidence = evidence.raw_text_or_visual_reference
        if not isinstance(locator, str) or not isinstance(raw_evidence, str):
            raise SnapshotBatchError(
                "snapshot candidate evidence must use textual locator/raw evidence",
                source_ref=source_record.source_id,
            )
        if locator not in blocks or blocks[locator] != raw_evidence:
            raise SnapshotBatchError(
                "candidate evidence does not match owning extraction document",
                source_ref=source_record.source_id,
            )
        expected_evidence_id = build_evidence_id(
            source_id=source_record.source_id,
            content_hash=source_record.content_hash,
            extraction_path=expected_path,
            field_name=evidence.field_name,
            locator=locator,
            extractor_fingerprint=evidence.extractor_version,
            raw_evidence=raw_evidence,
        )
        if evidence.evidence_id != expected_evidence_id:
            raise SnapshotBatchError(
                "candidate evidence identity does not match owning snapshot",
                source_ref=source_record.source_id,
            )

    return validated


def validate_snapshot_extraction_result(
    result: SnapshotExtractionResult,
) -> None:
    """Validate one extraction result as a coherent observation of one snapshot."""

    if not isinstance(result, SnapshotExtractionResult):
        raise SnapshotBatchError(
            "snapshot batch must contain SnapshotExtractionResult values"
        )
    snapshot = result.snapshot
    if not isinstance(snapshot, SourceSnapshot):
        raise SnapshotBatchError("snapshot extraction result has invalid snapshot")
    verify_snapshot_integrity(snapshot)

    native_document = result.native_document
    if not isinstance(native_document, NativeDocument):
        raise SnapshotBatchError("snapshot result requires a NativeDocument")
    _validate_document_source(
        snapshot=snapshot,
        document_source=native_document.source_record,
        path_name="native",
    )
    if native_document.media_type != snapshot.media_type:
        raise SnapshotBatchError(
            "native document media_type must match owning snapshot",
            source_ref=snapshot.source_record.source_id,
        )
    if native_document.raw_size_bytes != len(snapshot.content):
        raise SnapshotBatchError(
            "native document raw_size_bytes must match snapshot byte length",
            source_ref=snapshot.source_record.source_id,
        )

    if isinstance(snapshot.origin_metadata, HttpRetrievalMetadata):
        if native_document.retrieval != snapshot.origin_metadata:
            raise SnapshotBatchError(
                "native HTTP retrieval metadata must match owning snapshot",
                source_ref=snapshot.source_record.source_id,
            )
    elif isinstance(snapshot.origin_metadata, UploadedDocumentMetadata):
        if native_document.retrieval is not None:
            raise SnapshotBatchError(
                "uploaded native document must not invent HTTP retrieval metadata",
                source_ref=snapshot.source_record.source_id,
            )

    if not isinstance(result.bound_candidate_reports, tuple):
        raise SnapshotBatchError("bound_candidate_reports must be an immutable tuple")

    reports_by_path: dict[ExtractionPath, CandidateExtractionReport] = {}
    snapshot_source_id = snapshot.source_record.source_id
    for binding in result.bound_candidate_reports:
        if not isinstance(binding, SnapshotBoundCandidateReport):
            raise SnapshotBatchError(
                "snapshot result must contain snapshot-bound candidate reports"
            )
        if binding.snapshot_id != snapshot.snapshot_id:
            raise SnapshotBatchError(
                "candidate report binding must match owning snapshot_id",
                source_ref=snapshot_source_id,
            )
        raw_report = binding.report
        if raw_report.source_id != snapshot_source_id:
            raise SnapshotBatchError(
                "candidate report source_id must match owning snapshot source_id",
                source_ref=snapshot_source_id,
            )
        validated = _validated_report(raw_report)
        if binding.extraction_path is not validated.extraction_path:
            raise SnapshotBatchError(
                "candidate report binding path must match report extraction_path",
                source_ref=snapshot_source_id,
            )
        if validated.extraction_path in reports_by_path:
            raise SnapshotBatchError(
                "snapshot result must not contain duplicate extraction paths",
                source_ref=snapshot.source_record.source_id,
            )
        reports_by_path[validated.extraction_path] = raw_report

    if snapshot.media_type == "text/html":
        if result.ocr_document is not None:
            raise SnapshotBatchError(
                "HTML snapshot extraction must not contain an OCR document",
                source_ref=snapshot.source_record.source_id,
            )
        if set(reports_by_path) != {ExtractionPath.NATIVE}:
            raise SnapshotBatchError(
                "HTML snapshot result must contain exactly the native candidate path",
                source_ref=snapshot.source_record.source_id,
            )
        _validate_report_against_document(
            snapshot=snapshot,
            report=reports_by_path[ExtractionPath.NATIVE],
            document=native_document,
            expected_path=ExtractionPath.NATIVE,
        )
        return

    if snapshot.media_type != "application/pdf":
        raise SnapshotBatchError(
            f"unsupported snapshot media type: {snapshot.media_type}",
            source_ref=snapshot.source_record.source_id,
        )

    ocr_document = result.ocr_document
    if not isinstance(ocr_document, OCRDocument):
        raise SnapshotBatchError(
            "PDF snapshot result requires an OCRDocument",
            source_ref=snapshot.source_record.source_id,
        )
    _validate_document_source(
        snapshot=snapshot,
        document_source=ocr_document.source_record,
        path_name="OCR",
    )
    if set(reports_by_path) != {ExtractionPath.NATIVE, ExtractionPath.OCR}:
        raise SnapshotBatchError(
            "PDF snapshot result must contain exactly native and OCR candidate paths",
            source_ref=snapshot.source_record.source_id,
        )

    _validate_report_against_document(
        snapshot=snapshot,
        report=reports_by_path[ExtractionPath.NATIVE],
        document=native_document,
        expected_path=ExtractionPath.NATIVE,
    )
    _validate_report_against_document(
        snapshot=snapshot,
        report=reports_by_path[ExtractionPath.OCR],
        document=ocr_document,
        expected_path=ExtractionPath.OCR,
    )


def extract_snapshot(
    snapshot: SourceSnapshot,
    *,
    ocr_provider: OCRProvider | None = None,
    normalizer: CandidateReportNormalizer | None = None,
    native_kwargs: dict[str, Any] | None = None,
    ocr_kwargs: dict[str, Any] | None = None,
) -> SnapshotExtractionResult:
    """Fan one immutable snapshot out to independent extraction paths.

    HTML produces one native observation path. PDF always runs native and OCR
    independently; an empty report is preserved when a successful path finds no
    supported facts. Extraction failures propagate and are never rewritten as
    empty reports.
    """

    if not isinstance(snapshot, SourceSnapshot):
        raise SnapshotBatchError("snapshot must be a SourceSnapshot")
    verify_snapshot_integrity(snapshot)

    native_document = extract_native_snapshot(
        snapshot,
        **(native_kwargs or {}),
    )
    native_report = normalize_candidate_report(
        native_document,
        normalizer=normalizer,
    )

    if snapshot.media_type == "text/html":
        result = SnapshotExtractionResult(
            snapshot=snapshot,
            native_document=native_document,
            ocr_document=None,
            bound_candidate_reports=(
                SnapshotBoundCandidateReport(
                    snapshot_id=snapshot.snapshot_id,
                    extraction_path=ExtractionPath.NATIVE,
                    report=native_report,
                ),
            ),
        )
        validate_snapshot_extraction_result(result)
        return result

    if snapshot.media_type != "application/pdf":
        raise UnsupportedMediaTypeError(
            f"unsupported snapshot media type: {snapshot.media_type}",
            source_ref=snapshot.source_record.url_or_document_id,
        )

    ocr_document = extract_ocr_snapshot(
        snapshot,
        provider=ocr_provider,
        **(ocr_kwargs or {}),
    )
    ocr_report = normalize_candidate_report(
        ocr_document,
        normalizer=normalizer,
    )
    result = SnapshotExtractionResult(
        snapshot=snapshot,
        native_document=native_document,
        ocr_document=ocr_document,
        bound_candidate_reports=(
            SnapshotBoundCandidateReport(
                snapshot_id=snapshot.snapshot_id,
                extraction_path=ExtractionPath.NATIVE,
                report=native_report,
            ),
            SnapshotBoundCandidateReport(
                snapshot_id=snapshot.snapshot_id,
                extraction_path=ExtractionPath.OCR,
                report=ocr_report,
            ),
        ),
    )
    validate_snapshot_extraction_result(result)
    return result


def derive_snapshot_source_ids(
    results: Iterable[SnapshotExtractionResult],
) -> tuple[str, ...]:
    """Derive source IDs from one coherent extraction result per source snapshot."""

    if isinstance(results, (str, bytes)):
        raise SnapshotBatchError("snapshot results must be an iterable of results")
    try:
        items = tuple(results)
    except TypeError as exc:
        raise SnapshotBatchError("snapshot results must be iterable") from exc
    if not items:
        raise SnapshotBatchError("snapshot extraction result batch must not be empty")

    snapshot_by_source: dict[str, str] = {}
    source_ids: set[str] = set()

    for result in items:
        validate_snapshot_extraction_result(result)
        snapshot = result.snapshot
        source_id = snapshot.source_record.source_id
        prior_snapshot_id = snapshot_by_source.get(source_id)
        if prior_snapshot_id is not None:
            if prior_snapshot_id != snapshot.snapshot_id:
                raise SnapshotBatchError(
                    "one source_id cannot contribute multiple active snapshots",
                    source_ref=source_id,
                )
            raise SnapshotBatchError(
                "one source_id must contribute exactly one SnapshotExtractionResult",
                source_ref=source_id,
            )
        snapshot_by_source[source_id] = snapshot.snapshot_id
        source_ids.add(source_id)

    return tuple(sorted(source_ids))
