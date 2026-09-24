"""Internal native-ingestion models.

These are engine transport objects, not canonical competition facts.  They keep
retrieval details and document structure until semantic extraction creates
EvidenceSpan/CandidateExtractionReport objects in a later step.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from packages.contracts import SourceRecord, SourceType


@dataclass(frozen=True, slots=True)
class SourceContext:
    """Caller-supplied source metadata that ingestion must not guess."""

    source_id: str
    source_type: SourceType
    authority_rank: Any
    scope: Any
    freshness_metadata: Any


@dataclass(frozen=True, slots=True)
class RetrievalMetadata:
    """HTTP retrieval facts kept outside the SOURCE_SCHEMA wire contract."""

    requested_url: str
    resolved_url: str
    status_code: int
    content_type: str | None
    etag: str | None
    last_modified: str | None
    redirect_chain: tuple[str, ...] = ()


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

    @property
    def text(self) -> str:
        """Flatten native blocks for consumers that do not need structure."""

        return "\n".join(block.text for block in self.blocks)

    @property
    def has_native_text(self) -> bool:
        """Whether the native path observed at least one non-empty text block."""

        return bool(self.blocks)
