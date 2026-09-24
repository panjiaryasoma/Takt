"""Internal source-ingestion and extraction transport models.

These objects are intentionally not canonical competition facts. Block 4c adds
an immutable retrieval snapshot boundary so native and OCR paths can observe
exactly the same source bytes without sharing mutable SourceRecord instances.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import UTC, datetime
from hashlib import sha256
from typing import TYPE_CHECKING, Any, Iterable

from engine.extraction.errors import (
    InvalidSourceError,
    SnapshotIntegrityError,
    UnsupportedMediaTypeError,
)
from packages.contracts import (
    CandidateExtractionReport,
    ExtractionPath,
    SourceRecord,
    SourceType,
)

if TYPE_CHECKING:
    from engine.extraction.ocr.models import OCRDocument

_SUPPORTED_SNAPSHOT_MEDIA_TYPES = frozenset({"text/html", "application/pdf"})


@dataclass(frozen=True, slots=True)
class SourceContext:
    """Caller-supplied source metadata that ingestion must not guess."""

    source_id: str
    source_type: SourceType
    authority_rank: Any
    scope: Any
    freshness_metadata: Any


@dataclass(frozen=True, slots=True, init=False)
class HttpRetrievalMetadata:
    """Facts from one HTTP retrieval transaction.

    The custom constructor keeps the Block 2 ``content_type=`` API valid while
    allowing Block 4c to retain a separate declared charset hint. Redirect hops
    are canonicalized to an owned tuple so caller mutation cannot alter a
    snapshot after construction.
    """

    requested_url: str
    resolved_url: str
    status_code: int
    declared_content_type: str | None
    declared_charset: str | None
    etag: str | None
    last_modified: str | None
    redirect_chain: tuple[str, ...]

    def __init__(
        self,
        requested_url: str,
        resolved_url: str,
        status_code: int,
        content_type: str | None = None,
        etag: str | None = None,
        last_modified: str | None = None,
        redirect_chain: Iterable[str] = (),
        *,
        declared_content_type: str | None = None,
        declared_charset: str | None = None,
    ) -> None:
        if not isinstance(requested_url, str) or not requested_url.strip():
            raise ValueError("requested_url must be a non-empty string")
        if not isinstance(resolved_url, str) or not resolved_url.strip():
            raise ValueError("resolved_url must be a non-empty string")
        if isinstance(status_code, bool) or not isinstance(status_code, int):
            raise ValueError("status_code must be an integer")

        if content_type is not None and declared_content_type is not None:
            if content_type.strip().lower() != declared_content_type.strip().lower():
                raise ValueError(
                    "content_type and declared_content_type must not disagree"
                )
        selected_content_type = (
            declared_content_type if declared_content_type is not None else content_type
        )
        if selected_content_type is not None:
            if not isinstance(selected_content_type, str):
                raise ValueError("content_type must be a string or null")
            selected_content_type = selected_content_type.strip().lower() or None

        if declared_charset is not None:
            if not isinstance(declared_charset, str):
                raise ValueError("declared_charset must be a string or null")
            declared_charset = declared_charset.strip() or None

        if isinstance(redirect_chain, (str, bytes)):
            raise ValueError("redirect_chain must be an iterable of URLs")
        try:
            owned_chain = tuple(redirect_chain)
        except TypeError as exc:
            raise ValueError("redirect_chain must be iterable") from exc
        if any(not isinstance(item, str) or not item.strip() for item in owned_chain):
            raise ValueError("redirect_chain must contain non-empty URL strings")

        object.__setattr__(self, "requested_url", requested_url.strip())
        object.__setattr__(self, "resolved_url", resolved_url.strip())
        object.__setattr__(self, "status_code", status_code)
        object.__setattr__(self, "declared_content_type", selected_content_type)
        object.__setattr__(self, "declared_charset", declared_charset)
        object.__setattr__(self, "etag", etag)
        object.__setattr__(self, "last_modified", last_modified)
        object.__setattr__(self, "redirect_chain", owned_chain)

    @property
    def content_type(self) -> str | None:
        """Backward-compatible Block 2 name for declared media type."""

        return self.declared_content_type


# Backward-compatible import name used by the existing native extractors/tests.
RetrievalMetadata = HttpRetrievalMetadata


@dataclass(frozen=True, slots=True)
class UploadedDocumentMetadata:
    """Origin facts for caller-supplied document bytes without fake HTTP data."""

    document_id: str
    uploaded_at: datetime
    declared_media_type: str

    def __post_init__(self) -> None:
        if not isinstance(self.document_id, str) or not self.document_id.strip():
            raise ValueError("document_id must be a non-empty string")
        if not isinstance(self.uploaded_at, datetime):
            raise ValueError("uploaded_at must be a datetime")
        if self.uploaded_at.tzinfo is None or self.uploaded_at.utcoffset() is None:
            raise ValueError("uploaded_at must include timezone information")
        if (
            not isinstance(self.declared_media_type, str)
            or not self.declared_media_type.strip()
        ):
            raise ValueError("declared_media_type must be a non-empty string")
        object.__setattr__(self, "document_id", self.document_id.strip())
        object.__setattr__(
            self,
            "declared_media_type",
            self.declared_media_type.strip().lower(),
        )


SnapshotOriginMetadata = HttpRetrievalMetadata | UploadedDocumentMetadata


def _canonical_instant(value: datetime) -> str:
    if value.tzinfo is None or value.utcoffset() is None:
        raise InvalidSourceError("snapshot retrieval timestamp must include timezone")
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _snapshot_id_material(
    *,
    source_record: SourceRecord,
    media_type: str,
    origin_metadata: SnapshotOriginMetadata,
) -> str:
    origin_kind = (
        "http" if isinstance(origin_metadata, HttpRetrievalMetadata) else "upload"
    )
    material = [
        source_record.source_id,
        source_record.url_or_document_id,
        _canonical_instant(source_record.retrieved_at),
        source_record.content_hash,
        media_type,
        origin_kind,
    ]
    encoded = json.dumps(
        material,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    return f"snap-{sha256(encoded).hexdigest()}"


def _owned_origin_metadata(
    origin_metadata: SnapshotOriginMetadata,
) -> SnapshotOriginMetadata:
    if isinstance(origin_metadata, HttpRetrievalMetadata):
        return HttpRetrievalMetadata(
            requested_url=origin_metadata.requested_url,
            resolved_url=origin_metadata.resolved_url,
            status_code=origin_metadata.status_code,
            declared_content_type=origin_metadata.declared_content_type,
            declared_charset=origin_metadata.declared_charset,
            etag=origin_metadata.etag,
            last_modified=origin_metadata.last_modified,
            redirect_chain=origin_metadata.redirect_chain,
        )
    if isinstance(origin_metadata, UploadedDocumentMetadata):
        return UploadedDocumentMetadata(
            document_id=origin_metadata.document_id,
            uploaded_at=origin_metadata.uploaded_at,
            declared_media_type=origin_metadata.declared_media_type,
        )
    raise TypeError("origin_metadata must describe HTTP or upload origin")


def _verify_content_hash(*, source_record: SourceRecord, content: bytes) -> None:
    expected = source_record.content_hash.strip().lower()
    prefix = "sha256:"
    if not expected.startswith(prefix):
        raise SnapshotIntegrityError(
            "snapshot content_hash cannot be verified; expected sha256:<hex>",
            source_ref=source_record.url_or_document_id,
        )
    digest = expected[len(prefix) :]
    if len(digest) != 64:
        raise SnapshotIntegrityError(
            "snapshot content_hash is not a valid SHA-256 digest",
            source_ref=source_record.url_or_document_id,
        )
    try:
        int(digest, 16)
    except ValueError as exc:
        raise SnapshotIntegrityError(
            "snapshot content_hash is not a valid SHA-256 digest",
            source_ref=source_record.url_or_document_id,
        ) from exc
    if sha256(content).hexdigest() != digest:
        raise SnapshotIntegrityError(
            "snapshot bytes do not match SourceRecord content_hash",
            source_ref=source_record.url_or_document_id,
        )


def _validate_origin_consistency(
    *,
    source_record: SourceRecord,
    media_type: str,
    origin_metadata: SnapshotOriginMetadata,
) -> None:
    if isinstance(origin_metadata, HttpRetrievalMetadata):
        if source_record.url_or_document_id != origin_metadata.resolved_url:
            raise InvalidSourceError(
                "HTTP snapshot resolved_url must match SourceRecord source reference",
                source_ref=source_record.url_or_document_id,
            )
        return

    if source_record.url_or_document_id != origin_metadata.document_id:
        raise InvalidSourceError(
            "uploaded snapshot document_id must match SourceRecord source reference",
            source_ref=source_record.url_or_document_id,
        )
    if _canonical_instant(source_record.retrieved_at) != _canonical_instant(
        origin_metadata.uploaded_at
    ):
        raise InvalidSourceError(
            "uploaded snapshot timestamp must match SourceRecord retrieved_at",
            source_ref=source_record.url_or_document_id,
        )
    if origin_metadata.declared_media_type != media_type:
        raise InvalidSourceError(
            "uploaded snapshot declared media type must match snapshot media type",
            source_ref=source_record.url_or_document_id,
        )


@dataclass(frozen=True, slots=True, init=False)
class SourceSnapshot:
    """One immutable retrieval event and exact byte payload.

    ``snapshot_id`` identifies the retrieval event, not all semantic metadata in
    SourceRecord. Authority/scope/freshness can therefore be reinterpreted
    without pretending the source bytes were retrieved again.
    """

    snapshot_id: str
    media_type: str
    content: bytes
    origin_metadata: SnapshotOriginMetadata
    _source_record: SourceRecord

    def __init__(
        self,
        *,
        source_record: SourceRecord,
        media_type: str,
        content: bytes,
        origin_metadata: SnapshotOriginMetadata,
        snapshot_id: str | None = None,
    ) -> None:
        if not isinstance(source_record, SourceRecord):
            raise TypeError("source_record must be a SourceRecord")
        if not isinstance(media_type, str) or not media_type.strip():
            raise ValueError("media_type must be a non-empty string")
        normalized_media_type = media_type.strip().lower()
        if normalized_media_type not in _SUPPORTED_SNAPSHOT_MEDIA_TYPES:
            raise UnsupportedMediaTypeError(
                f"unsupported snapshot media type: {normalized_media_type}",
                source_ref=source_record.url_or_document_id,
            )
        if not isinstance(content, bytes):
            raise TypeError("snapshot content must be bytes")

        owned_record = source_record.model_copy(deep=True)
        owned_origin = _owned_origin_metadata(origin_metadata)
        owned_content = bytes(content)

        _verify_content_hash(source_record=owned_record, content=owned_content)
        _validate_origin_consistency(
            source_record=owned_record,
            media_type=normalized_media_type,
            origin_metadata=owned_origin,
        )

        computed_id = _snapshot_id_material(
            source_record=owned_record,
            media_type=normalized_media_type,
            origin_metadata=owned_origin,
        )
        if snapshot_id is not None and snapshot_id != computed_id:
            raise ValueError("snapshot_id does not match retrieval identity material")

        object.__setattr__(self, "snapshot_id", computed_id)
        object.__setattr__(self, "media_type", normalized_media_type)
        object.__setattr__(self, "content", owned_content)
        object.__setattr__(self, "origin_metadata", owned_origin)
        object.__setattr__(self, "_source_record", owned_record)

    @property
    def source_record(self) -> SourceRecord:
        """Return a deep-independent copy of the snapshot-owned SourceRecord."""

        return self._source_record.model_copy(deep=True)

    def source_record_material(self) -> dict[str, Any]:
        """Stable material view for equality/tests without exposing internal alias."""

        return self._source_record.model_dump(mode="python")


@dataclass(frozen=True, slots=True)
class NativeTextBlock:
    """One native text fragment with a deterministic source locator."""

    locator: str
    text: str
    kind: str
    page_number: int | None = None
    bounding_box: tuple[float, float, float, float] | None = None


@dataclass(frozen=True, slots=True)
class NativeDocument:
    """Native parse result before semantic field extraction."""

    source_record: SourceRecord
    media_type: str
    raw_size_bytes: int
    blocks: tuple[NativeTextBlock, ...]
    page_count: int | None = None
    pages_without_native_text: tuple[int, ...] = ()
    retrieval: RetrievalMetadata | None = None
    parser_version: str = "native-unknown-v1"

    @property
    def text(self) -> str:
        """Flatten native blocks for consumers that do not need structure."""

        return "\n".join(block.text for block in self.blocks)

    @property
    def has_native_text(self) -> bool:
        """Whether the native path observed at least one non-empty text block."""

        return bool(self.blocks)


@dataclass(frozen=True, slots=True)
class SnapshotBoundCandidateReport:
    """Internal binding from one candidate report to its source snapshot."""

    snapshot_id: str
    extraction_path: ExtractionPath
    report: CandidateExtractionReport

    def __post_init__(self) -> None:
        if not isinstance(self.snapshot_id, str) or not self.snapshot_id.strip():
            raise ValueError("snapshot_id must be a non-empty string")
        if not isinstance(self.extraction_path, ExtractionPath):
            raise TypeError("extraction_path must be an ExtractionPath")
        if not isinstance(self.report, CandidateExtractionReport):
            raise TypeError("report must be a CandidateExtractionReport")
        object.__setattr__(self, "snapshot_id", self.snapshot_id.strip())
        object.__setattr__(self, "report", self.report.model_copy(deep=True))


@dataclass(frozen=True, slots=True)
class SnapshotExtractionResult:
    """Independent native/OCR observations produced from one SourceSnapshot."""

    snapshot: SourceSnapshot
    native_document: NativeDocument
    ocr_document: OCRDocument | None
    bound_candidate_reports: tuple[SnapshotBoundCandidateReport, ...]

    @property
    def candidate_reports(self) -> tuple[CandidateExtractionReport, ...]:
        """Expose candidate reports without dropping their internal snapshot binding."""

        return tuple(binding.report for binding in self.bound_candidate_reports)
