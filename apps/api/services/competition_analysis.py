"""Issue 4A source-analysis application service for public API routes."""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass

import httpx

from apps.api.contracts import (
    AnalysisProvenanceV1,
    CanonicalReportBundleV1,
    CanonicalReportRefV1,
    CompetitionAnalyzePdfMetadataV1,
    CompetitionAnalyzeResponseV1,
    CompetitionAnalyzeUrlRequestV1,
    ExtractionRunAuditV1,
    SourceMetadataV1,
)
from apps.api.fingerprints import report_wire_fingerprint
from engine.extraction import (
    SnapshotExtractionResult,
    SourceContext,
    create_pdf_snapshot,
    extract_snapshot,
    fetch_url_snapshot,
)
from engine.extraction.candidate_normalizer import extractor_fingerprint_for_document
from engine.integration.competition_analysis import build_canonical_report
from apps.api.services.plan_evaluation import (
    ReportBundleError,
    UnsupportedReportContractError,
    verify_report_bundle,
)
from engine.reconciliation.models import ReconciliationInputError
from packages.contracts import EvidenceSpan, ExtractionPath, SourceRecord


class AnalysisInputError(ValueError):
    """Client-owned analysis metadata is inconsistent before extraction."""


class AnalysisReconciliationError(RuntimeError):
    """Server-produced extraction material could not be reconciled."""


class AnalysisInvariantError(RuntimeError):
    """Analysis output lost required provenance or traceability."""


@dataclass(frozen=True, slots=True)
class _PreviousReport:
    bundle: CanonicalReportBundleV1 | None

    @property
    def report(self):
        return self.bundle.report if self.bundle is not None else None

    @property
    def material_fingerprint(self) -> str | None:
        if self.bundle is None:
            return None
        return self.bundle.ref.assembly_material_fingerprint


def _source_context(source: SourceMetadataV1) -> SourceContext:
    return SourceContext(
        source_id=source.source_id,
        source_type=source.source_type,
        authority_rank=source.authority_rank,
        scope=source.scope,
        freshness_metadata=source.freshness_metadata,
    )


def _previous_report(
    *,
    competition_id: str,
    bundle: CanonicalReportBundleV1 | None,
) -> _PreviousReport:
    if bundle is None:
        return _PreviousReport(None)
    verify_report_bundle(bundle)
    if bundle.ref.competition_id != competition_id:
        raise ReportBundleError(
            "previous report competition_id does not match analysis request"
        )
    return _PreviousReport(bundle)


def _extraction_runs(
    result: SnapshotExtractionResult,
) -> tuple[ExtractionRunAuditV1, ...]:
    source_id = result.snapshot.source_record.source_id
    runs = [
        ExtractionRunAuditV1(
            source_id=source_id,
            snapshot_id=result.snapshot.snapshot_id,
            extraction_path=ExtractionPath.NATIVE,
            extractor_version=extractor_fingerprint_for_document(
                result.native_document
            ),
        )
    ]
    if result.ocr_document is not None:
        runs.append(
            ExtractionRunAuditV1(
                source_id=source_id,
                snapshot_id=result.snapshot.snapshot_id,
                extraction_path=ExtractionPath.OCR,
                extractor_version=extractor_fingerprint_for_document(
                    result.ocr_document
                ),
            )
        )
    return tuple(runs)


def _evidence(
    results: Iterable[SnapshotExtractionResult],
) -> tuple[EvidenceSpan, ...]:
    by_id: dict[str, EvidenceSpan] = {}
    for result in results:
        for report in result.candidate_reports:
            for evidence in report.evidence:
                existing = by_id.get(evidence.evidence_id)
                if existing is not None and existing != evidence:
                    raise AnalysisInvariantError(
                        "duplicate evidence ID maps to conflicting evidence"
                    )
                by_id[evidence.evidence_id] = evidence
    return tuple(by_id[key] for key in sorted(by_id))


def _sources(
    results: Iterable[SnapshotExtractionResult],
) -> tuple[SourceRecord, ...]:
    by_id: dict[str, SourceRecord] = {}
    for result in results:
        record = result.snapshot.source_record
        existing = by_id.get(record.source_id)
        if existing is not None and existing != record:
            raise AnalysisInvariantError(
                "one source ID maps to conflicting source records"
            )
        by_id[record.source_id] = record
    return tuple(by_id[key] for key in sorted(by_id))


def _assert_canonical_evidence_resolves(
    report,
    evidence: tuple[EvidenceSpan, ...],
) -> None:
    available = {item.evidence_id for item in evidence}
    referenced = {
        evidence_id
        for field in report.canonical_fields.values()
        for evidence_id in field.evidence_ids
    }
    missing = referenced.difference(available)
    if missing:
        raise AnalysisInvariantError(
            "canonical report references evidence absent from API provenance"
        )


def _report_bundle(assembly) -> CanonicalReportBundleV1:
    initial_ref = CanonicalReportRefV1(
        competition_id=assembly.report.competition_id,
        report_version=assembly.report.report_version,
        reconciliation_policy_version="reconciliation-v1",
        assembly_policy_version=assembly.assembly_policy_version,
        assembly_material_fingerprint=assembly.material_fingerprint,
        wire_fingerprint_version="report-wire-jcs-sha256-v1",
        wire_fingerprint="0" * 64,
    )
    fingerprint = report_wire_fingerprint(assembly.report, initial_ref)
    ref = initial_ref.model_copy(update={"wire_fingerprint": fingerprint})
    return CanonicalReportBundleV1(report=assembly.report, ref=ref)


def _response(
    *,
    competition_id: str,
    results: tuple[SnapshotExtractionResult, ...],
    previous: _PreviousReport,
) -> CompetitionAnalyzeResponseV1:
    try:
        assembly = build_canonical_report(
            competition_id=competition_id,
            snapshot_results=results,
            previous_report=previous.report,
            previous_material_fingerprint=previous.material_fingerprint,
        )
    except ReconciliationInputError as exc:
        raise AnalysisReconciliationError(
            "server-produced extraction material failed reconciliation"
        ) from exc

    evidence = _evidence(results)
    _assert_canonical_evidence_resolves(assembly.report, evidence)
    provenance = AnalysisProvenanceV1(
        sources=_sources(results),
        extraction_runs=tuple(
            run
            for result in results
            for run in _extraction_runs(result)
        ),
        evidence=evidence,
    )
    return CompetitionAnalyzeResponseV1(
        report_bundle=_report_bundle(assembly),
        provenance=provenance,
        report_changed=assembly.report_changed,
    )


def analyze_url(
    request: CompetitionAnalyzeUrlRequestV1,
    *,
    client: httpx.Client | None = None,
) -> CompetitionAnalyzeResponseV1:
    previous = _previous_report(
        competition_id=request.competition_id,
        bundle=request.previous_report_bundle,
    )
    snapshot = fetch_url_snapshot(
        request.url,
        context=_source_context(request.source),
        client=client,
    )
    result = extract_snapshot(snapshot)
    return _response(
        competition_id=request.competition_id,
        results=(result,),
        previous=previous,
    )


def analyze_pdf(
    metadata: CompetitionAnalyzePdfMetadataV1,
    content: bytes,
) -> CompetitionAnalyzeResponseV1:
    previous = _previous_report(
        competition_id=metadata.competition_id,
        bundle=metadata.previous_report_bundle,
    )
    snapshot = create_pdf_snapshot(
        metadata.document_id,
        content,
        context=_source_context(metadata.source),
    )
    result = extract_snapshot(snapshot)
    return _response(
        competition_id=metadata.competition_id,
        results=(result,),
        previous=previous,
    )


__all__ = [
    "AnalysisInputError",
    "AnalysisInvariantError",
    "AnalysisReconciliationError",
    "ReportBundleError",
    "UnsupportedReportContractError",
    "analyze_pdf",
    "analyze_url",
]
