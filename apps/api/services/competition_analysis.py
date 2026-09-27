"""Issue 4A source-analysis application service for public API routes."""

from __future__ import annotations

import hmac
from collections.abc import Iterable
from dataclasses import dataclass

import httpx

from apps.api.contracts import (
    AnalysisProvenanceV1,
    RECONCILIATION_POLICY_VERSION,
    CanonicalReportBundleV1,
    CanonicalReportRefV1,
    CompetitionAnalyzePdfMetadataV1,
    CompetitionAnalyzeResponseV1,
    CompetitionAnalyzeUrlRequestV1,
    ExtractionRunAuditV1,
    SourceAnalysisArtifactV1,
    SourceMetadataV1,
)
from apps.api.fingerprints import report_wire_fingerprint, source_set_fingerprint
from engine.extraction import (
    OCRProvider,
    SnapshotExtractionResult,
    SourceContext,
    create_pdf_snapshot,
    extract_snapshot,
    fetch_url_snapshot,
)
from engine.extraction.candidate_normalizer import extractor_fingerprint_for_document
from engine.reconciliation import (
    CANONICAL_V1,
    assemble_canonical_report,
    reconcile_field,
)
from apps.api.services.plan_evaluation import (
    ReportBundleError,
    UnsupportedReportContractError,
    verify_report_bundle,
)
from engine.reconciliation.models import ReconciliationInputError
from engine.reconciliation.policy import validate_source_policy_metadata
from packages.contracts import (
    CandidateExtractionReport,
    EvidenceSpan,
    ExtractionPath,
    SourceRecord,
)


class AnalysisInputError(ValueError):
    """Client-owned analysis metadata is inconsistent before extraction."""


class AnalysisContinuationError(ValueError):
    """Previous report and source-set continuation material disagree."""


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


def _validate_source_metadata(source: SourceMetadataV1) -> None:
    try:
        validate_source_policy_metadata(
            source_type=source.source_type,
            authority_rank=source.authority_rank,
            scope=source.scope,
            freshness_metadata=source.freshness_metadata,
        )
    except ReconciliationInputError as exc:
        raise AnalysisInputError(
            "source policy metadata failed domain validation"
        ) from exc


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
    prior_source_artifacts: tuple[SourceAnalysisArtifactV1, ...],
) -> _PreviousReport:
    if bundle is None:
        if prior_source_artifacts:
            raise AnalysisContinuationError(
                "prior source artifacts require previous_report_bundle"
            )
        return _PreviousReport(None)

    verify_report_bundle(bundle)
    if bundle.ref.competition_id != competition_id:
        raise ReportBundleError(
            "previous report competition_id does not match analysis request"
        )

    prior_ids = tuple(
        sorted(artifact.source.source_id for artifact in prior_source_artifacts)
    )
    if len(set(prior_ids)) != len(prior_ids):
        raise AnalysisContinuationError(
            "prior source artifact IDs must be unique"
        )
    report_ids = tuple(sorted(bundle.report.source_ids))
    if prior_ids != report_ids:
        raise AnalysisContinuationError(
            "prior source artifacts must exactly cover previous report source_ids"
        )

    if bundle.ref.source_set_fingerprint is None:
        raise AnalysisContinuationError(
            "previous report bundle is not bound to a source artifact set"
        )
    try:
        expected_source_set_fingerprint = source_set_fingerprint(
            prior_source_artifacts
        )
        for artifact in prior_source_artifacts:
            validate_source_policy_metadata(
                source_type=artifact.source.source_type,
                authority_rank=artifact.source.authority_rank,
                scope=artifact.source.scope,
                freshness_metadata=artifact.source.freshness_metadata,
            )
    except (ReconciliationInputError, TypeError, ValueError) as exc:
        raise AnalysisContinuationError(
            "prior source artifacts failed continuation validation"
        ) from exc

    if not hmac.compare_digest(
        expected_source_set_fingerprint,
        bundle.ref.source_set_fingerprint,
    ):
        raise AnalysisContinuationError(
            "prior source artifacts do not match previous report source-set fingerprint"
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


def _artifact_from_result(
    result: SnapshotExtractionResult,
) -> SourceAnalysisArtifactV1:
    return SourceAnalysisArtifactV1(
        source=result.snapshot.source_record,
        candidate_reports=tuple(result.candidate_reports),
        extraction_runs=_extraction_runs(result),
    )


def _merge_source_artifacts(
    prior: tuple[SourceAnalysisArtifactV1, ...],
    current: SourceAnalysisArtifactV1,
) -> tuple[SourceAnalysisArtifactV1, ...]:
    by_id = {artifact.source.source_id: artifact for artifact in prior}
    by_id[current.source.source_id] = current
    return tuple(by_id[source_id] for source_id in sorted(by_id))


def _candidate_reports(
    artifacts: Iterable[SourceAnalysisArtifactV1],
) -> tuple[CandidateExtractionReport, ...]:
    return tuple(
        report
        for artifact in artifacts
        for report in artifact.candidate_reports
    )


def _evidence(
    artifacts: Iterable[SourceAnalysisArtifactV1],
) -> tuple[EvidenceSpan, ...]:
    by_id: dict[str, EvidenceSpan] = {}
    for report in _candidate_reports(artifacts):
        for evidence in report.evidence:
            existing = by_id.get(evidence.evidence_id)
            if existing is not None and existing != evidence:
                raise AnalysisInvariantError(
                    "duplicate evidence ID maps to conflicting evidence"
                )
            by_id[evidence.evidence_id] = evidence
    return tuple(by_id[key] for key in sorted(by_id))


def _sources(
    artifacts: Iterable[SourceAnalysisArtifactV1],
) -> tuple[SourceRecord, ...]:
    by_id: dict[str, SourceRecord] = {}
    for artifact in artifacts:
        record = artifact.source
        existing = by_id.get(record.source_id)
        if existing is not None and existing != record:
            raise AnalysisInvariantError(
                "one source ID maps to conflicting source records"
            )
        by_id[record.source_id] = record
    return tuple(by_id[key] for key in sorted(by_id))


def _build_canonical_from_artifacts(
    *,
    competition_id: str,
    artifacts: tuple[SourceAnalysisArtifactV1, ...],
    previous: _PreviousReport,
):
    reports = _candidate_reports(artifacts)
    sources = _sources(artifacts)
    field_results = tuple(
        reconcile_field(
            field_name,
            reports=reports,
            sources=sources,
        )
        for field_name in CANONICAL_V1.core_fields
    )
    return assemble_canonical_report(
        competition_id=competition_id,
        field_results=field_results,
        snapshot_source_ids=tuple(item.source_id for item in sources),
        previous_report=previous.report,
        previous_material_fingerprint=previous.material_fingerprint,
        policy=CANONICAL_V1,
    )


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


def _report_bundle(
    assembly,
    artifacts: tuple[SourceAnalysisArtifactV1, ...],
) -> CanonicalReportBundleV1:
    initial_ref = CanonicalReportRefV1(
        competition_id=assembly.report.competition_id,
        report_version=assembly.report.report_version,
        reconciliation_policy_version=RECONCILIATION_POLICY_VERSION,
        assembly_policy_version=assembly.assembly_policy_version,
        assembly_material_fingerprint=assembly.material_fingerprint,
        source_set_fingerprint=source_set_fingerprint(artifacts),
        wire_fingerprint_version="report-wire-jcs-sha256-v1",
        wire_fingerprint="0" * 64,
    )
    fingerprint = report_wire_fingerprint(assembly.report, initial_ref)
    ref = initial_ref.model_copy(update={"wire_fingerprint": fingerprint})
    return CanonicalReportBundleV1(report=assembly.report, ref=ref)


def _response(
    *,
    competition_id: str,
    result: SnapshotExtractionResult,
    prior_source_artifacts: tuple[SourceAnalysisArtifactV1, ...],
    previous: _PreviousReport,
) -> CompetitionAnalyzeResponseV1:
    current = _artifact_from_result(result)
    artifacts = _merge_source_artifacts(prior_source_artifacts, current)
    try:
        assembly = _build_canonical_from_artifacts(
            competition_id=competition_id,
            artifacts=artifacts,
            previous=previous,
        )
    except ReconciliationInputError as exc:
        raise AnalysisReconciliationError(
            "source-set material failed reconciliation"
        ) from exc

    evidence = _evidence(artifacts)
    _assert_canonical_evidence_resolves(assembly.report, evidence)
    provenance = AnalysisProvenanceV1(
        sources=_sources(artifacts),
        extraction_runs=tuple(
            run
            for artifact in artifacts
            for run in artifact.extraction_runs
        ),
        evidence=evidence,
    )
    return CompetitionAnalyzeResponseV1(
        report_bundle=_report_bundle(assembly, artifacts),
        source_artifacts=artifacts,
        provenance=provenance,
        report_changed=assembly.report_changed,
    )


def analyze_url(
    request: CompetitionAnalyzeUrlRequestV1,
    *,
    client: httpx.Client | None = None,
) -> CompetitionAnalyzeResponseV1:
    _validate_source_metadata(request.source)
    previous = _previous_report(
        competition_id=request.competition_id,
        bundle=request.previous_report_bundle,
        prior_source_artifacts=request.prior_source_artifacts,
    )
    snapshot = fetch_url_snapshot(
        request.url,
        context=_source_context(request.source),
        client=client,
    )
    result = extract_snapshot(snapshot)
    return _response(
        competition_id=request.competition_id,
        result=result,
        prior_source_artifacts=request.prior_source_artifacts,
        previous=previous,
    )


def analyze_pdf(
    metadata: CompetitionAnalyzePdfMetadataV1,
    content: bytes,
    *,
    ocr_provider: OCRProvider | None = None,
) -> CompetitionAnalyzeResponseV1:
    _validate_source_metadata(metadata.source)
    previous = _previous_report(
        competition_id=metadata.competition_id,
        bundle=metadata.previous_report_bundle,
        prior_source_artifacts=metadata.prior_source_artifacts,
    )
    snapshot = create_pdf_snapshot(
        metadata.document_id,
        content,
        context=_source_context(metadata.source),
    )
    result = extract_snapshot(snapshot, ocr_provider=ocr_provider)
    return _response(
        competition_id=metadata.competition_id,
        result=result,
        prior_source_artifacts=metadata.prior_source_artifacts,
        previous=previous,
    )


__all__ = [
    "AnalysisContinuationError",
    "AnalysisInputError",
    "AnalysisInvariantError",
    "AnalysisReconciliationError",
    "ReportBundleError",
    "UnsupportedReportContractError",
    "analyze_pdf",
    "analyze_url",
]
