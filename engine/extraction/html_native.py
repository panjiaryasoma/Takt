"""Deterministic native HTML text extraction using the standard library."""

from __future__ import annotations

import codecs
import re
from collections import defaultdict
from dataclasses import dataclass, field
from html.parser import HTMLParser
from urllib.parse import quote

from engine.extraction.errors import SourceLimitExceededError
from engine.extraction.models import NativeDocument, NativeTextBlock, RetrievalMetadata
from packages.contracts import SourceRecord

_BLOCK_TAGS = {
    "address",
    "article",
    "aside",
    "blockquote",
    "body",
    "button",
    "caption",
    "dd",
    "details",
    "dialog",
    "div",
    "dl",
    "dt",
    "fieldset",
    "figcaption",
    "figure",
    "footer",
    "form",
    "h1",
    "h2",
    "h3",
    "h4",
    "h5",
    "h6",
    "header",
    "hgroup",
    "legend",
    "li",
    "main",
    "menu",
    "nav",
    "ol",
    "optgroup",
    "option",
    "p",
    "pre",
    "search",
    "section",
    "select",
    "summary",
    "svg",
    "table",
    "tbody",
    "td",
    "tfoot",
    "th",
    "thead",
    "title",
    "tr",
    "text",
    "tspan",
    "ul",
}
_CONTEXT_TAGS = {"main", "article", "section"}
_IGNORED_TAGS = {"script", "style", "noscript", "template"}
_VOID_TAGS = {
    "area",
    "base",
    "br",
    "col",
    "embed",
    "hr",
    "img",
    "input",
    "link",
    "meta",
    "param",
    "source",
    "track",
    "wbr",
}
_LIST_SCOPE_BOUNDARY_TAGS = {"menu", "ol", "ul"}
_P_IMPLIED_END_START_TAGS = {
    "address",
    "article",
    "aside",
    "blockquote",
    "body",
    "div",
    "dl",
    "fieldset",
    "footer",
    "form",
    "h1",
    "h2",
    "h3",
    "h4",
    "h5",
    "h6",
    "header",
    "hr",
    "main",
    "nav",
    "ol",
    "p",
    "pre",
    "section",
    "table",
    "ul",
}
_CSS_COMMENT_RE = re.compile(r"/\*.*?\*/", re.DOTALL)


def _normalize_whitespace(value: str) -> str:
    return " ".join(value.split())


def _escape_locator_id(value: str) -> str:
    """Escape document-controlled IDs out of the locator suffix namespace."""

    return quote(value, safe="-._~")


def _style_hides_element(value: str | None) -> bool:
    """Detect only explicit inline `display: none` declarations.

    This deliberately does not treat `aria-hidden` as visual hiding and does
    not try to implement the CSS cascade. False negatives are safer here than
    silently discarding textual evidence that may still be visible.
    """

    if not value:
        return False

    cleaned = _CSS_COMMENT_RE.sub("", value)
    for declaration in cleaned.split(";"):
        property_name, separator, raw_value = declaration.partition(":")
        if not separator or property_name.strip().lower() != "display":
            continue
        css_value = raw_value.strip().lower()
        if css_value.endswith("!important"):
            css_value = css_value[: -len("!important")].strip()
        if css_value == "none":
            return True
    return False


def _element_is_hidden(attrs: dict[str, str | None]) -> bool:
    if "hidden" in attrs:
        return True
    return _style_hides_element(attrs.get("style"))


@dataclass(slots=True)
class _Frame:
    tag: str
    element_id: str | None
    locator: str | None
    hidden: bool
    parts: list[str] = field(default_factory=list)
    emitted_segments: int = 0


class _NativeHTMLParser(HTMLParser):
    def __init__(self, *, max_blocks: int, max_text_chars: int) -> None:
        super().__init__(convert_charrefs=True)
        if max_blocks <= 0 or max_text_chars <= 0:
            raise ValueError("native HTML resource limits must be greater than zero")
        self.blocks: list[NativeTextBlock] = []
        self._max_blocks = max_blocks
        self._max_text_chars = max_text_chars
        self._visible_text_chars_seen = 0
        self._tag_counts: dict[str, int] = defaultdict(int)
        self._locator_counts: dict[str, int] = defaultdict(int)
        self._stack: list[_Frame] = [
            _Frame(
                tag="document",
                element_id=None,
                locator="document[1]",
                hidden=False,
            )
        ]

    def _nearest_visible_block(self) -> _Frame | None:
        for frame in reversed(self._stack):
            if frame.hidden:
                return None
            if frame.locator is not None:
                return frame
        return None

    def _flush(self, frame: _Frame) -> None:
        if frame.hidden or frame.locator is None or not frame.parts:
            frame.parts.clear()
            return
        text = _normalize_whitespace("".join(frame.parts))
        frame.parts.clear()
        if not text:
            return
        if len(self.blocks) >= self._max_blocks:
            raise SourceLimitExceededError(
                f"native HTML exceeded block limit of {self._max_blocks}"
            )
        frame.emitted_segments += 1
        locator = frame.locator
        if frame.emitted_segments > 1:
            locator = f"{locator}::segment:{frame.emitted_segments}"
        self.blocks.append(NativeTextBlock(locator=locator, text=text, kind=frame.tag))

    def _pop_from(self, index: int) -> None:
        while len(self._stack) > index:
            frame = self._stack.pop()
            self._flush(frame)

    def _close_nearest(self, tag: str) -> None:
        for index in range(len(self._stack) - 1, -1, -1):
            if self._stack[index].tag == tag:
                self._pop_from(index)
                return

    def _close_open_list_item_in_same_scope(self) -> None:
        for index in range(len(self._stack) - 1, -1, -1):
            frame = self._stack[index]
            if frame.tag == "li":
                self._pop_from(index)
                return
            if frame.tag in _LIST_SCOPE_BOUNDARY_TAGS:
                return

    def _apply_implied_end_tags(self, tag: str) -> None:
        if tag == "li":
            self._close_open_list_item_in_same_scope()
        if tag in _P_IMPLIED_END_START_TAGS:
            self._close_nearest("p")

    def _locator_for(self, tag: str, element_id: str | None) -> str:
        own = (
            f"{tag}#{_escape_locator_id(element_id)}"
            if element_id
            else f"{tag}[{self._tag_counts[tag]}]"
        )
        context = [
            f"{frame.tag}#{_escape_locator_id(frame.element_id)}"
            for frame in self._stack
            if frame.tag in _CONTEXT_TAGS and frame.element_id and not frame.hidden
        ]
        base_locator = " > ".join([*context, own])
        self._locator_counts[base_locator] += 1
        occurrence = self._locator_counts[base_locator]
        if occurrence == 1:
            return base_locator
        return f"{base_locator}::occurrence:{occurrence}"

    def handle_starttag(
        self,
        tag: str,
        attrs: list[tuple[str, str | None]],
    ) -> None:
        tag = tag.lower()
        attrs_dict = dict(attrs)
        parent_hidden = self._stack[-1].hidden if self._stack else False
        hidden = parent_hidden or tag in _IGNORED_TAGS or _element_is_hidden(attrs_dict)

        if tag == "br":
            if not hidden:
                active = self._nearest_visible_block()
                if active is not None:
                    active.parts.append(" ")
            return

        if tag == "hr":
            if not hidden:
                self._apply_implied_end_tags(tag)
                active = self._nearest_visible_block()
                if active is not None:
                    self._flush(active)
            return

        self._apply_implied_end_tags(tag)

        # HTML void elements never own child content and normally have no closing tag.
        # Keeping one on the stack would incorrectly make following siblings inherit
        # its hidden state (for example <img aria-hidden="true">).
        if tag in _VOID_TAGS:
            return

        if tag in _BLOCK_TAGS and not hidden:
            parent_block = self._nearest_visible_block()
            if parent_block is not None:
                self._flush(parent_block)

        self._tag_counts[tag] += 1
        element_id = attrs_dict.get("id")
        locator = None
        if tag in _BLOCK_TAGS and not hidden:
            locator = self._locator_for(tag, element_id)
        self._stack.append(
            _Frame(
                tag=tag,
                element_id=element_id,
                locator=locator,
                hidden=hidden,
            )
        )

    def handle_startendtag(
        self,
        tag: str,
        attrs: list[tuple[str, str | None]],
    ) -> None:
        if tag.lower() == "br":
            self.handle_starttag(tag, attrs)
            return
        self.handle_starttag(tag, attrs)
        self.handle_endtag(tag)

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()
        for index in range(len(self._stack) - 1, -1, -1):
            if self._stack[index].tag == tag:
                self._pop_from(index)
                return

    def handle_data(self, data: str) -> None:
        active = self._nearest_visible_block()
        if active is not None:
            self._visible_text_chars_seen += len(data)
            if self._visible_text_chars_seen > self._max_text_chars:
                raise SourceLimitExceededError(
                    f"native HTML exceeded extracted text limit of {self._max_text_chars}"
                )
            active.parts.append(data)

    def finish(self) -> None:
        self._pop_from(0)


class _MetaCharsetParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=False)
        self.charset: str | None = None

    def handle_starttag(
        self,
        tag: str,
        attrs: list[tuple[str, str | None]],
    ) -> None:
        if self.charset is not None or tag.lower() != "meta":
            return
        attrs_dict = {name.lower(): value for name, value in attrs}
        direct = attrs_dict.get("charset")
        if direct and direct.strip():
            self.charset = direct.strip()
            return

        http_equiv = (attrs_dict.get("http-equiv") or "").strip().lower()
        content = attrs_dict.get("content") or ""
        if http_equiv != "content-type":
            return
        for parameter in content.split(";")[1:]:
            name, separator, value = parameter.partition("=")
            if separator and name.strip().lower() == "charset" and value.strip():
                self.charset = value.strip().strip('"\'')
                return


def _declared_meta_charset(content: bytes) -> str | None:
    # Latin-1 preserves ASCII markup byte-for-byte while allowing arbitrary
    # undecoded bytes to pass through the tokenizer. HTMLParser therefore sees
    # actual <meta> elements but ignores fake markup inside comments/scripts.
    parser = _MetaCharsetParser()
    try:
        parser.feed(content[:8192].decode("latin1"))
        parser.close()
    except (UnicodeError, ValueError):
        return None
    return parser.charset


def _decode_html(content: bytes, encoding: str | None) -> str:
    if content.startswith(codecs.BOM_UTF8):
        return content.decode("utf-8-sig")
    if content.startswith((codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE)):
        return content.decode("utf-16")

    candidates: list[str] = []
    if encoding:
        candidates.append(encoding)
    meta_charset = _declared_meta_charset(content)
    if meta_charset:
        candidates.append(meta_charset)
    candidates.extend(["utf-8", "windows-1252"])

    seen: set[str] = set()
    for candidate in candidates:
        normalized = candidate.strip().lower()
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        try:
            return content.decode(candidate)
        except (LookupError, UnicodeDecodeError):
            continue
    return content.decode("utf-8", errors="replace")


def extract_html_native(
    content: bytes,
    *,
    source_record: SourceRecord,
    encoding: str | None = None,
    retrieval: RetrievalMetadata | None = None,
    max_blocks: int = 20_000,
    max_text_chars: int = 5_000_000,
) -> NativeDocument:
    """Extract static textual structure from HTML without OCR or JS execution."""

    parser = _NativeHTMLParser(max_blocks=max_blocks, max_text_chars=max_text_chars)
    parser.feed(_decode_html(content, encoding))
    parser.close()
    parser.finish()
    return NativeDocument(
        source_record=source_record,
        media_type="text/html",
        raw_size_bytes=len(content),
        blocks=tuple(parser.blocks),
        retrieval=retrieval,
    )
