"""Shared boundary from extraction observations to CandidateExtractionReport."""

from __future__ import annotations

from typing import Protocol

from engine.extraction.errors import CandidateNormalizationError
from engine.extraction.models import NativeDocument
from engine.extraction.ocr.models import OCRDocument
from packages.contracts import CandidateExtractionReport, ExtractionPath

type ExtractionDocument = NativeDocument | OCRDocument


class CandidateReportNormalizer(Protocol):
    """Semantic normalization boundary shared by native and OCR paths."""

    def normalize(
        self,
        document: ExtractionDocument,
        *,
        extraction_path: ExtractionPath,
    ) -> CandidateExtractionReport: ...


def normalize_candidate_report(
    document: ExtractionDocument,
    *,
    normalizer: CandidateReportNormalizer | None = None,
) -> CandidateExtractionReport:
    """Normalize an observation document into the shared candidate contract.

    A deterministic rule-based normalizer is used by default so the public OCR
    path can produce a real CandidateExtractionReport without test-only stubs.
    Callers may inject another normalizer through the same boundary.
    """

    if isinstance(document, NativeDocument):
        extraction_path = ExtractionPath.NATIVE
    elif isinstance(document, OCRDocument):
        extraction_path = ExtractionPath.OCR
    else:
        raise CandidateNormalizationError(
            "document must be NativeDocument or OCRDocument"
        )

    if normalizer is None:
        from engine.extraction.candidate_normalizer import RuleBasedCandidateNormalizer

        active_normalizer: CandidateReportNormalizer = RuleBasedCandidateNormalizer()
    else:
        active_normalizer = normalizer

    try:
        report = active_normalizer.normalize(
            document,
            extraction_path=extraction_path,
        )
    except CandidateNormalizationError:
        raise
    except Exception as exc:
        raise CandidateNormalizationError(
            "candidate normalizer failed",
            source_ref=document.source_record.url_or_document_id,
        ) from exc

    if not isinstance(report, CandidateExtractionReport):
        raise CandidateNormalizationError(
            "candidate normalizer must return CandidateExtractionReport",
            source_ref=document.source_record.url_or_document_id,
        )
    if report.source_id != document.source_record.source_id:
        raise CandidateNormalizationError(
            "candidate report source_id must match extraction source_id",
            source_ref=document.source_record.url_or_document_id,
        )
    if report.extraction_path is not extraction_path:
        raise CandidateNormalizationError(
            "candidate report extraction_path must match observation path",
            source_ref=document.source_record.url_or_document_id,
        )
    return report
