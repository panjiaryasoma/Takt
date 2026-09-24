"""Native source ingestion orchestration for ordinary HTML and PDF sources."""

from __future__ import annotations

from datetime import UTC, datetime
from hashlib import sha256
from urllib.parse import urljoin, urlsplit

import httpx
from pydantic import ValidationError

from engine.extraction.errors import (
    InvalidSourceError,
    SnapshotIntegrityError,
    SourceFetchError,
    SourceLimitExceededError,
    UnsupportedMediaTypeError,
)
from engine.extraction.html_native import extract_html_native
from engine.extraction.models import (
    HttpRetrievalMetadata,
    NativeDocument,
    SourceContext,
    SourceSnapshot,
    UploadedDocumentMetadata,
)
from engine.extraction.pdf_native import extract_pdf_native
from engine.extraction.url_security import (
    validate_http_url_reference,
    validate_public_http_target,
)
from packages.contracts import SourceRecord, SourceType

_REDIRECT_STATUS = {301, 302, 303, 307, 308}
_MAX_REDIRECTS = 5
_GENERIC_BINARY_MEDIA_TYPES = {"application/octet-stream", "binary/octet-stream"}
MAX_SOURCE_BYTES = 20 * 1024 * 1024
MAX_PDF_PAGES = 250
MAX_NATIVE_BLOCKS = 20_000
MAX_EXTRACTED_TEXT_CHARS = 5_000_000


def _validate_native_extraction_limits(
    *,
    max_native_blocks: int,
    max_extracted_text_chars: int,
) -> None:
    if max_native_blocks <= 0 or max_extracted_text_chars <= 0:
        raise InvalidSourceError("native extraction limits must be greater than zero")


def _content_hash(content: bytes) -> str:
    return f"sha256:{sha256(content).hexdigest()}"


def _validate_source_context(context: SourceContext) -> SourceType:
    if not isinstance(context, SourceContext):
        raise InvalidSourceError("context must be a SourceContext")
    if not isinstance(context.source_id, str) or not context.source_id.strip():
        raise InvalidSourceError("source_id must be a non-empty string")
    try:
        source_type = SourceType(context.source_type)
    except (TypeError, ValueError) as exc:
        raise InvalidSourceError("source_type must be a supported SourceType") from exc
    for name in ("authority_rank", "scope", "freshness_metadata"):
        if getattr(context, name) is None:
            raise InvalidSourceError(f"{name} must be explicit and must not be null")
    return source_type


def _media_type(response: httpx.Response) -> str | None:
    value = response.headers.get("content-type")
    if not value:
        return None
    return value.split(";", 1)[0].strip().lower() or None


def _http_declared_charset(response: httpx.Response) -> str | None:
    value = response.headers.get("content-type")
    if not value:
        return None
    for parameter in value.split(";")[1:]:
        name, separator, raw_value = parameter.partition("=")
        if separator and name.strip().lower() == "charset":
            charset = raw_value.strip().strip('"\'')
            return charset or None
    return None


def _detect_supported_media_type(response: httpx.Response, content: bytes) -> str:
    media_type = _media_type(response)

    if media_type == "text/html":
        return "text/html"
    if media_type == "application/pdf":
        return "application/pdf"

    should_sniff = media_type is None or media_type in _GENERIC_BINARY_MEDIA_TYPES
    if should_sniff and content.lstrip().startswith(b"%PDF-"):
        return "application/pdf"
    if should_sniff:
        prefix = content[:1024].lstrip().lower()
        if prefix.startswith(b"<!doctype html") or b"<html" in prefix:
            return "text/html"

    raise UnsupportedMediaTypeError(
        f"unsupported source media type: {media_type or 'unknown'}",
        source_ref=str(response.url),
    )


def _declared_content_length(response: httpx.Response) -> int | None:
    raw_value = response.headers.get("content-length")
    if raw_value is None:
        return None
    try:
        value = int(raw_value)
    except ValueError:
        return None
    return value if value >= 0 else None


def _read_limited_content(
    response: httpx.Response,
    *,
    max_source_bytes: int,
) -> bytes:
    if max_source_bytes <= 0:
        raise InvalidSourceError("max_source_bytes must be greater than zero")

    declared_length = _declared_content_length(response)
    if declared_length is not None and declared_length > max_source_bytes:
        raise SourceLimitExceededError(
            f"source exceeded byte limit of {max_source_bytes}",
            source_ref=str(response.url),
        )

    collected = bytearray()
    try:
        for chunk in response.iter_bytes():
            if len(collected) + len(chunk) > max_source_bytes:
                raise SourceLimitExceededError(
                    f"source exceeded byte limit of {max_source_bytes}",
                    source_ref=str(response.url),
                )
            collected.extend(chunk)
    except SourceLimitExceededError:
        raise
    except httpx.HTTPError as exc:
        raise SourceFetchError(
            "source response body could not be read",
            source_ref=str(response.url),
        ) from exc
    return bytes(collected)


def _reject_transport_downgrade(current_url: str, next_url: str) -> None:
    current_scheme = urlsplit(current_url).scheme.lower()
    next_scheme = urlsplit(next_url).scheme.lower()
    if current_scheme == "https" and next_scheme == "http":
        raise SourceFetchError(
            "HTTPS source redirected to insecure HTTP",
            source_ref=current_url,
        )


def _fetch_response(
    url: str,
    *,
    client: httpx.Client,
    max_source_bytes: int,
) -> tuple[httpx.Response, bytes, tuple[str, ...]]:
    current_url = url
    redirect_chain: list[str] = []

    for redirect_count in range(_MAX_REDIRECTS + 1):
        validate_public_http_target(current_url)
        try:
            with client.stream("GET", current_url, follow_redirects=False) as response:
                if response.status_code in _REDIRECT_STATUS:
                    location = response.headers.get("location")
                    if not location:
                        raise SourceFetchError(
                            "source redirect did not include a location",
                            source_ref=current_url,
                        )
                    if redirect_count == _MAX_REDIRECTS:
                        raise SourceFetchError(
                            f"source exceeded {_MAX_REDIRECTS} redirects",
                            source_ref=url,
                        )
                    next_url = urljoin(str(response.url), location)
                    validate_http_url_reference(next_url)
                    _reject_transport_downgrade(str(response.url), next_url)
                    redirect_chain.append(str(response.url))
                    current_url = next_url
                    continue

                if response.status_code == 206:
                    raise SourceFetchError(
                        "source returned unexpected HTTP 206 Partial Content",
                        source_ref=current_url,
                    )

                if response.is_error:
                    raise SourceFetchError(
                        f"source returned HTTP {response.status_code}",
                        source_ref=current_url,
                    )

                content = _read_limited_content(
                    response,
                    max_source_bytes=max_source_bytes,
                )
                return response, content, tuple(redirect_chain)
        except InvalidSourceError:
            raise
        except httpx.InvalidURL as exc:
            raise InvalidSourceError(
                "source URL is malformed",
                source_ref=current_url,
            ) from exc
        except httpx.HTTPError as exc:
            raise SourceFetchError(
                "source URL could not be retrieved",
                source_ref=current_url,
            ) from exc

    raise SourceFetchError("source redirect handling failed", source_ref=url)


def _source_record(
    *,
    context: SourceContext,
    source_type: SourceType,
    source_ref: str,
    content: bytes,
    retrieved_at: datetime,
) -> SourceRecord:
    try:
        return SourceRecord(
            source_id=context.source_id,
            source_type=source_type,
            url_or_document_id=source_ref,
            retrieved_at=retrieved_at,
            content_hash=_content_hash(content),
            authority_rank=context.authority_rank,
            scope=context.scope,
            freshness_metadata=context.freshness_metadata,
        )
    except ValidationError as exc:
        raise InvalidSourceError(
            "source metadata failed SourceRecord validation",
            source_ref=source_ref,
        ) from exc


def verify_snapshot_integrity(snapshot: SourceSnapshot) -> None:
    source_record = snapshot.source_record
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
    if sha256(snapshot.content).hexdigest() != digest:
        raise SnapshotIntegrityError(
            "snapshot bytes do not match SourceRecord content_hash",
            source_ref=source_record.url_or_document_id,
        )


def fetch_url_snapshot(
    url: str,
    *,
    context: SourceContext,
    client: httpx.Client | None = None,
    retrieved_at: datetime | None = None,
    max_source_bytes: int = MAX_SOURCE_BYTES,
) -> SourceSnapshot:
    """Perform one HTTP retrieval transaction and freeze the final response body.

    Redirect hops remain part of this single transaction. Callers must fan out
    native/OCR work from the returned snapshot rather than retrieving again.
    """

    source_type = _validate_source_context(context)
    validate_http_url_reference(url)
    owned_client = client is None
    active_client = client or httpx.Client(timeout=15.0)

    try:
        response, content, redirect_chain = _fetch_response(
            url,
            client=active_client,
            max_source_bytes=max_source_bytes,
        )
        media_type = _detect_supported_media_type(response, content)
        timestamp = retrieved_at or datetime.now(UTC)
        resolved_url = str(response.url)
        source_record = _source_record(
            context=context,
            source_type=source_type,
            source_ref=resolved_url,
            content=content,
            retrieved_at=timestamp,
        )
        retrieval = HttpRetrievalMetadata(
            requested_url=url,
            resolved_url=resolved_url,
            status_code=response.status_code,
            declared_content_type=_media_type(response),
            declared_charset=_http_declared_charset(response),
            etag=response.headers.get("etag"),
            last_modified=response.headers.get("last-modified"),
            redirect_chain=redirect_chain,
        )
        snapshot = SourceSnapshot(
            source_record=source_record,
            media_type=media_type,
            content=content,
            origin_metadata=retrieval,
        )
        verify_snapshot_integrity(snapshot)
        return snapshot
    finally:
        if owned_client:
            active_client.close()


def create_pdf_snapshot(
    document_id: str,
    content: bytes,
    *,
    context: SourceContext,
    retrieved_at: datetime | None = None,
    max_source_bytes: int = MAX_SOURCE_BYTES,
) -> SourceSnapshot:
    """Freeze caller-supplied PDF bytes without inventing HTTP metadata."""

    source_type = _validate_source_context(context)
    if not isinstance(document_id, str) or not document_id.strip():
        raise InvalidSourceError("document_id must be a non-empty string")
    if not isinstance(content, bytes):
        raise InvalidSourceError("PDF content must be bytes", source_ref=document_id)
    if max_source_bytes <= 0:
        raise InvalidSourceError("max_source_bytes must be greater than zero")
    if len(content) > max_source_bytes:
        raise SourceLimitExceededError(
            f"source exceeded byte limit of {max_source_bytes}",
            source_ref=document_id,
        )

    timestamp = retrieved_at or datetime.now(UTC)
    source_record = _source_record(
        context=context,
        source_type=source_type,
        source_ref=document_id,
        content=content,
        retrieved_at=timestamp,
    )
    metadata = UploadedDocumentMetadata(
        document_id=document_id,
        uploaded_at=timestamp,
        declared_media_type="application/pdf",
    )
    snapshot = SourceSnapshot(
        source_record=source_record,
        media_type="application/pdf",
        content=content,
        origin_metadata=metadata,
    )
    verify_snapshot_integrity(snapshot)
    return snapshot


def extract_native_snapshot(
    snapshot: SourceSnapshot,
    *,
    max_pdf_pages: int = MAX_PDF_PAGES,
    max_native_blocks: int = MAX_NATIVE_BLOCKS,
    max_extracted_text_chars: int = MAX_EXTRACTED_TEXT_CHARS,
) -> NativeDocument:
    """Run native parsing against the exact bytes owned by one snapshot."""

    if not isinstance(snapshot, SourceSnapshot):
        raise InvalidSourceError("snapshot must be a SourceSnapshot")
    _validate_native_extraction_limits(
        max_native_blocks=max_native_blocks,
        max_extracted_text_chars=max_extracted_text_chars,
    )

    verify_snapshot_integrity(snapshot)
    source_record = snapshot.source_record
    retrieval = (
        snapshot.origin_metadata
        if isinstance(snapshot.origin_metadata, HttpRetrievalMetadata)
        else None
    )

    if snapshot.media_type == "text/html":
        encoding = retrieval.declared_charset if retrieval is not None else None
        return extract_html_native(
            snapshot.content,
            source_record=source_record,
            encoding=encoding,
            retrieval=retrieval,
            max_blocks=max_native_blocks,
            max_text_chars=max_extracted_text_chars,
        )
    if snapshot.media_type == "application/pdf":
        return extract_pdf_native(
            snapshot.content,
            source_record=source_record,
            retrieval=retrieval,
            max_pages=max_pdf_pages,
            max_blocks=max_native_blocks,
            max_text_chars=max_extracted_text_chars,
        )
    raise UnsupportedMediaTypeError(
        f"unsupported snapshot media type: {snapshot.media_type}",
        source_ref=source_record.url_or_document_id,
    )


def ingest_url_native(
    url: str,
    *,
    context: SourceContext,
    client: httpx.Client | None = None,
    retrieved_at: datetime | None = None,
    max_source_bytes: int = MAX_SOURCE_BYTES,
    max_pdf_pages: int = MAX_PDF_PAGES,
    max_native_blocks: int = MAX_NATIVE_BLOCKS,
    max_extracted_text_chars: int = MAX_EXTRACTED_TEXT_CHARS,
) -> NativeDocument:
    """Backward-compatible URL native API backed by SourceSnapshot."""

    # Preserve the Block 2 pre-fetch validation order for this public wrapper.
    _validate_source_context(context)
    validate_http_url_reference(url)
    _validate_native_extraction_limits(
        max_native_blocks=max_native_blocks,
        max_extracted_text_chars=max_extracted_text_chars,
    )

    snapshot = fetch_url_snapshot(
        url,
        context=context,
        client=client,
        retrieved_at=retrieved_at,
        max_source_bytes=max_source_bytes,
    )
    return extract_native_snapshot(
        snapshot,
        max_pdf_pages=max_pdf_pages,
        max_native_blocks=max_native_blocks,
        max_extracted_text_chars=max_extracted_text_chars,
    )


def ingest_pdf_native(
    document_id: str,
    content: bytes,
    *,
    context: SourceContext,
    retrieved_at: datetime | None = None,
    max_source_bytes: int = MAX_SOURCE_BYTES,
    max_pdf_pages: int = MAX_PDF_PAGES,
    max_native_blocks: int = MAX_NATIVE_BLOCKS,
    max_extracted_text_chars: int = MAX_EXTRACTED_TEXT_CHARS,
) -> NativeDocument:
    """Backward-compatible uploaded-PDF native API backed by SourceSnapshot."""

    # Preserve the Block 2 validation order before constructing a snapshot.
    _validate_source_context(context)
    if not isinstance(document_id, str) or not document_id.strip():
        raise InvalidSourceError("document_id must be a non-empty string")
    if not isinstance(content, bytes):
        raise InvalidSourceError("PDF content must be bytes", source_ref=document_id)
    if max_source_bytes <= 0:
        raise InvalidSourceError("max_source_bytes must be greater than zero")
    _validate_native_extraction_limits(
        max_native_blocks=max_native_blocks,
        max_extracted_text_chars=max_extracted_text_chars,
    )
    if len(content) > max_source_bytes:
        raise SourceLimitExceededError(
            f"source exceeded byte limit of {max_source_bytes}",
            source_ref=document_id,
        )

    snapshot = create_pdf_snapshot(
        document_id,
        content,
        context=context,
        retrieved_at=retrieved_at,
        max_source_bytes=max_source_bytes,
    )
    return extract_native_snapshot(
        snapshot,
        max_pdf_pages=max_pdf_pages,
        max_native_blocks=max_native_blocks,
        max_extracted_text_chars=max_extracted_text_chars,
    )
