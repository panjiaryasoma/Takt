from __future__ import annotations

import socket
from datetime import UTC, datetime
from pathlib import Path

import httpx
import pymupdf
import pytest

from engine.extraction import (
    InvalidSourceError,
    NativeExtractionError,
    SourceContext,
    SourceFetchError,
    UnsupportedMediaTypeError,
    ingest_pdf_native,
    ingest_url_native,
)
from packages.contracts import SourceType

FIXTURES = Path(__file__).parents[1] / "fixtures" / "extraction"
FIXED_TIME = datetime(2026, 9, 24, 1, 0, tzinfo=UTC)


def _context(source_id: str = "src-native-001") -> SourceContext:
    return SourceContext(
        source_id=source_id,
        source_type=SourceType.DERIVED_FIXTURE,
        authority_rank={"kind": "fixture"},
        scope={"competition": "fixture"},
        freshness_metadata={"fixture_version": 1},
    )


def _client(handler) -> httpx.Client:
    return httpx.Client(transport=httpx.MockTransport(handler))


@pytest.fixture(autouse=True)
def _fixture_example_domains_resolve_publicly(monkeypatch: pytest.MonkeyPatch) -> None:
    def public_getaddrinfo(
        host: str,
        port: int,
        *args: object,
        **kwargs: object,
    ) -> list[tuple[int, int, int, str, tuple[str, int]]]:
        return [
            (
                socket.AF_INET,
                socket.SOCK_STREAM,
                socket.IPPROTO_TCP,
                "",
                ("93.184.216.34", port),
            )
        ]

    monkeypatch.setattr(
        "engine.extraction.url_security.socket.getaddrinfo",
        public_getaddrinfo,
    )


def test_url_html_ingestion_preserves_structure_and_retrieval_metadata() -> None:
    html = (FIXTURES / "native_competition.html").read_bytes()

    def handler(request: httpx.Request) -> httpx.Response:
        assert str(request.url) == "https://fixture.example/rules"
        return httpx.Response(
            200,
            headers={
                "content-type": "text/html; charset=utf-8",
                "etag": '"fixture-v1"',
                "last-modified": "Wed, 23 Sep 2026 10:00:00 GMT",
            },
            content=html,
            request=request,
        )

    with _client(handler) as client:
        document = ingest_url_native(
            "https://fixture.example/rules",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    assert document.media_type == "text/html"
    assert document.has_native_text is True
    assert document.source_record.retrieved_at == FIXED_TIME
    assert document.source_record.url_or_document_id == "https://fixture.example/rules"
    assert document.source_record.content_hash.startswith("sha256:")
    assert "Takt Fixture Hackathon" in document.text
    assert "window.notEvidence" not in document.text
    assert any(
        block.locator == "main#competition > h1#competition-title"
        for block in document.blocks
    )
    assert any(
        block.locator == "main#competition > section#deadline > p[1]"
        for block in document.blocks
    )
    assert document.retrieval is not None
    assert document.retrieval.etag == '"fixture-v1"'
    assert document.retrieval.last_modified == "Wed, 23 Sep 2026 10:00:00 GMT"


def test_url_adapter_validates_each_redirect_target_before_following() -> None:
    calls: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(str(request.url))
        return httpx.Response(
            302,
            headers={"location": "http://127.0.0.1/internal"},
            request=request,
        )

    with _client(handler) as client, pytest.raises(InvalidSourceError, match="non-public IP"):
        ingest_url_native(
            "https://fixture.example/start",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    assert calls == ["https://fixture.example/start"]


def test_url_adapter_rejects_non_http_scheme_before_network() -> None:
    with pytest.raises(InvalidSourceError, match="http or https"):
        ingest_url_native(
            "file:///tmp/rules.html",
            context=_context(),
            retrieved_at=FIXED_TIME,
        )


def test_url_adapter_rejects_localhost_before_network() -> None:
    with pytest.raises(InvalidSourceError, match="local source URLs"):
        ingest_url_native(
            "http://localhost/rules",
            context=_context(),
            retrieved_at=FIXED_TIME,
        )


def test_url_adapter_wraps_http_failure_with_explicit_error() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(404, request=request)

    with _client(handler) as client:
        with pytest.raises(SourceFetchError, match="HTTP 404") as caught:
            ingest_url_native(
                "https://fixture.example/missing",
                context=_context(),
                client=client,
                retrieved_at=FIXED_TIME,
            )

    assert caught.value.code == "SOURCE_FETCH_FAILED"


def test_url_adapter_rejects_unsupported_media_type_cleanly() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "image/png"},
            content=b"not-a-supported-native-source",
            request=request,
        )

    with _client(handler) as client:
        with pytest.raises(UnsupportedMediaTypeError, match="image/png"):
            ingest_url_native(
                "https://fixture.example/banner.png",
                context=_context(),
                client=client,
                retrieved_at=FIXED_TIME,
            )


def test_url_adapter_can_sniff_pdf_when_server_uses_generic_binary_type() -> None:
    pdf = (FIXTURES / "native_competition.pdf").read_bytes()

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "application/octet-stream"},
            content=pdf,
            request=request,
        )

    with _client(handler) as client:
        document = ingest_url_native(
            "https://fixture.example/rules.bin",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    assert document.media_type == "application/pdf"
    assert document.page_count == 2
    assert {block.page_number for block in document.blocks} == {1, 2}


def test_pdf_upload_preserves_page_and_block_provenance() -> None:
    pdf = (FIXTURES / "native_competition.pdf").read_bytes()
    document = ingest_pdf_native(
        "upload/native_competition.pdf",
        pdf,
        context=_context("src-pdf-001"),
        retrieved_at=FIXED_TIME,
    )

    assert document.media_type == "application/pdf"
    assert document.page_count == 2
    assert document.pages_without_native_text == ()
    assert "Submission deadline" in document.text
    assert any(block.locator.startswith("page:1:block:") for block in document.blocks)
    assert any(block.locator.startswith("page:2:block:") for block in document.blocks)
    assert all(block.bounding_box is not None for block in document.blocks)
    assert document.source_record.url_or_document_id == "upload/native_competition.pdf"


def test_pdf_native_marks_pages_without_selectable_text_for_later_ocr() -> None:
    generated = pymupdf.open()
    generated.new_page()
    pdf = generated.tobytes()
    generated.close()

    document = ingest_pdf_native(
        "upload/image-only-placeholder.pdf",
        pdf,
        context=_context("src-pdf-empty"),
        retrieved_at=FIXED_TIME,
    )

    assert document.page_count == 1
    assert document.has_native_text is False
    assert document.pages_without_native_text == (1,)


def test_corrupt_pdf_fails_as_native_extraction_error() -> None:
    with pytest.raises(NativeExtractionError, match="could not be opened") as caught:
        ingest_pdf_native(
            "upload/broken.pdf",
            b"%PDF-this-is-not-a-real-pdf",
            context=_context("src-pdf-broken"),
            retrieved_at=FIXED_TIME,
        )

    assert caught.value.code == "NATIVE_EXTRACTION_FAILED"


def test_content_hash_is_deterministic_but_contract_does_not_require_sha_shape() -> None:
    pdf = (FIXTURES / "native_competition.pdf").read_bytes()
    first = ingest_pdf_native(
        "upload/a.pdf",
        pdf,
        context=_context("src-hash-a"),
        retrieved_at=FIXED_TIME,
    )
    second = ingest_pdf_native(
        "upload/b.pdf",
        pdf,
        context=_context("src-hash-b"),
        retrieved_at=FIXED_TIME,
    )

    assert first.source_record.content_hash == second.source_record.content_hash
    assert first.source_record.content_hash.startswith("sha256:")


def test_source_context_does_not_allow_ingestion_to_invent_required_metadata() -> None:
    bad_context = SourceContext(
        source_id="src-bad",
        source_type=SourceType.DERIVED_FIXTURE,
        authority_rank=None,
        scope={},
        freshness_metadata={},
    )

    with pytest.raises(InvalidSourceError, match="authority_rank"):
        ingest_pdf_native(
            "upload/native_competition.pdf",
            (FIXTURES / "native_competition.pdf").read_bytes(),
            context=bad_context,
            retrieved_at=FIXED_TIME,
        )


def test_html_nested_blocks_preserve_parent_text_before_and_after_child() -> None:
    html = b"<html><body><ul><li>prefix<p>inner</p>suffix</li></ul></body></html>"

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html; charset=utf-8"},
            content=html,
            request=request,
        )

    with _client(handler) as client:
        document = ingest_url_native(
            "https://fixture.example/nested",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    assert "prefix" in document.text
    assert "inner" in document.text
    assert "suffix" in document.text
    assert (
        document.text.index("prefix")
        < document.text.index("inner")
        < document.text.index("suffix")
    )


def test_html_optional_li_end_tags_preserve_list_text() -> None:
    html = b"<html><body><ul><li>one<li>two</ul></body></html>"

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html"},
            content=html,
            request=request,
        )

    with _client(handler) as client:
        document = ingest_url_native(
            "https://fixture.example/list",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    assert [block.text for block in document.blocks if block.kind == "li"] == ["one", "two"]


def test_html_optional_p_end_tags_preserve_paragraph_text() -> None:
    html = b"<html><body><p>one<p>two</body></html>"

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html"},
            content=html,
            request=request,
        )

    with _client(handler) as client:
        document = ingest_url_native(
            "https://fixture.example/paragraphs",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    assert [block.text for block in document.blocks if block.kind == "p"] == ["one", "two"]


def test_html_br_becomes_text_separator() -> None:
    html = b"<html><body><p>line1<br>line2</p></body></html>"

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html"},
            content=html,
            request=request,
        )

    with _client(handler) as client:
        document = ingest_url_native(
            "https://fixture.example/br",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    assert document.text == "line1 line2"


def test_html_div_text_is_not_dropped() -> None:
    html = b'<html><body><div class="deadline">Deadline Sep 30</div></body></html>'

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html"},
            content=html,
            request=request,
        )

    with _client(handler) as client:
        document = ingest_url_native(
            "https://fixture.example/div",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    assert "Deadline Sep 30" in document.text
    assert any(block.kind == "div" for block in document.blocks)


@pytest.mark.parametrize(
    "url",
    [
        "http://[::1",
        "http://[zzz]/x",
        "https://example.com:bad/x",
    ],
)
def test_malformed_urls_are_normalized_to_invalid_source_error(url: str) -> None:
    with pytest.raises(InvalidSourceError):
        ingest_url_native(url, context=_context(), retrieved_at=FIXED_TIME)


def test_html_meta_charset_is_honored_when_http_header_has_no_charset() -> None:
    html = (
        '<html><head><meta charset="windows-1252"></head>'
        '<body><p>Caf\xe9 \x97 deadline</p></body></html>'
    ).encode("latin1")

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html"},
            content=html,
            request=request,
        )

    with _client(handler) as client:
        document = ingest_url_native(
            "https://fixture.example/charset",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    assert "Café — deadline" in document.text
    assert "�" not in document.text


def test_obvious_hidden_html_is_filtered_without_treating_aria_hidden_as_visual() -> None:
    html = b"""
    <html><body>
      <p>visible</p>
      <p hidden>secret-one</p>
      <div aria-hidden="true"><p>visible-to-sighted-users</p></div>
      <div style="display:none"><p>secret-two</p></div>
    </body></html>
    """

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html"},
            content=html,
            request=request,
        )

    with _client(handler) as client:
        document = ingest_url_native(
            "https://fixture.example/hidden",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    assert "visible" in document.text
    assert "visible-to-sighted-users" in document.text
    assert "secret-one" not in document.text
    assert "secret-two" not in document.text


def test_inline_style_hidden_detection_parses_declarations_not_substrings() -> None:
    html = b"""
    <body>
      <p style="--foo: display:none">custom-property-is-visible</p>
      <p style="color:red; /* display:none */">comment-is-visible</p>
      <p style="display : none !important">actually-hidden</p>
    </body>
    """

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html"},
            content=html,
            request=request,
        )

    with _client(handler) as client:
        document = ingest_url_native(
            "https://fixture.example/style-hidden",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    assert "custom-property-is-visible" in document.text
    assert "comment-is-visible" in document.text
    assert "actually-hidden" not in document.text


def test_url_response_is_rejected_when_streamed_body_exceeds_size_limit() -> None:
    payload = b"<html><body><p>" + (b"x" * 128) + b"</p></body></html>"

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html"},
            content=payload,
            request=request,
        )

    from engine.extraction import SourceLimitExceededError

    with _client(handler) as client:
        with pytest.raises(SourceLimitExceededError, match="byte limit"):
            ingest_url_native(
                "https://fixture.example/large",
                context=_context(),
                client=client,
                retrieved_at=FIXED_TIME,
                max_source_bytes=64,
            )


def test_pdf_upload_is_rejected_before_parse_when_it_exceeds_size_limit() -> None:
    from engine.extraction import SourceLimitExceededError

    with pytest.raises(SourceLimitExceededError, match="byte limit"):
        ingest_pdf_native(
            "upload/too-large.pdf",
            b"%PDF-" + (b"x" * 128),
            context=_context("src-pdf-large"),
            retrieved_at=FIXED_TIME,
            max_source_bytes=64,
        )


def test_redirect_uses_final_resolved_url_as_source_record_provenance() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if str(request.url) == "https://a.example/start":
            return httpx.Response(
                302,
                headers={"location": "https://b.example/final"},
                request=request,
            )
        return httpx.Response(
            200,
            headers={"content-type": "text/html"},
            content=b"<html><body><p>final source</p></body></html>",
            request=request,
        )

    with _client(handler) as client:
        document = ingest_url_native(
            "https://a.example/start",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    assert document.source_record.url_or_document_id == "https://b.example/final"
    assert document.retrieval is not None
    assert document.retrieval.requested_url == "https://a.example/start"
    assert document.retrieval.resolved_url == "https://b.example/final"
    assert document.retrieval.redirect_chain == ("https://a.example/start",)


def test_source_context_none_source_id_is_normalized_to_invalid_source_error() -> None:
    bad_context = SourceContext(
        source_id=None,  # type: ignore[arg-type]
        source_type=SourceType.DERIVED_FIXTURE,
        authority_rank={},
        scope={},
        freshness_metadata={},
    )

    with pytest.raises(InvalidSourceError, match="source_id"):
        ingest_pdf_native(
            "upload/native_competition.pdf",
            (FIXTURES / "native_competition.pdf").read_bytes(),
            context=bad_context,
            retrieved_at=FIXED_TIME,
        )


def test_source_context_invalid_source_type_is_normalized_to_invalid_source_error() -> None:
    bad_context = SourceContext(
        source_id="src-bad-type",
        source_type="bogus",  # type: ignore[arg-type]
        authority_rank={},
        scope={},
        freshness_metadata={},
    )

    with pytest.raises(InvalidSourceError, match="source_type"):
        ingest_pdf_native(
            "upload/native_competition.pdf",
            (FIXTURES / "native_competition.pdf").read_bytes(),
            context=bad_context,
            retrieved_at=FIXED_TIME,
        )


def test_pdf_page_count_limit_is_explicit_ingestion_error() -> None:
    generated = pymupdf.open()
    generated.new_page()
    generated.new_page()
    generated.new_page()
    pdf = generated.tobytes()
    generated.close()

    from engine.extraction import SourceLimitExceededError

    with pytest.raises(SourceLimitExceededError, match="page limit"):
        ingest_pdf_native(
            "upload/too-many-pages.pdf",
            pdf,
            context=_context("src-pdf-pages"),
            retrieved_at=FIXED_TIME,
            max_pdf_pages=2,
        )


def test_hidden_void_element_does_not_hide_following_siblings() -> None:
    html = b"""
    <html><body>
      <p>before</p>
      <img aria-hidden="true">
      <input hidden>
      <p>after</p>
    </body></html>
    """

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html; charset=utf-8"},
            content=html,
            request=request,
        )

    with _client(handler) as client:
        document = ingest_url_native(
            "https://fixture.example/hidden-void",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    assert "before" in document.text
    assert "after" in document.text


def test_nested_list_returns_following_text_to_outer_li_locator() -> None:
    html = b"""
    <html><body>
      <ul>
        <li>outer before<ul><li>inner</li></ul>outer after</li>
      </ul>
    </body></html>
    """

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html; charset=utf-8"},
            content=html,
            request=request,
        )

    with _client(handler) as client:
        document = ingest_url_native(
            "https://fixture.example/nested-list",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    before = next(block for block in document.blocks if block.text == "outer before")
    inner = next(block for block in document.blocks if block.text == "inner")
    after = next(block for block in document.blocks if block.text == "outer after")

    assert before.kind == "li"
    assert inner.kind == "li"
    assert after.kind == "li"
    assert before.locator.split("::segment:", 1)[0] == after.locator.split(
        "::segment:", 1
    )[0]


def test_root_inline_fragment_is_preserved_as_visible_text() -> None:
    html = b"<span>Deadline Sep 30</span>"

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html; charset=utf-8"},
            content=html,
            request=request,
        )

    with _client(handler) as client:
        document = ingest_url_native(
            "https://fixture.example/inline-fragment",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    assert document.text == "Deadline Sep 30"
    assert len(document.blocks) == 1
    assert document.blocks[0].locator == "document[1]"
    assert document.blocks[0].kind == "document"


def test_duplicate_html_ids_get_deterministic_unique_locators() -> None:
    html = b"""
    <html><body>
      <section id="x"><p id="y">A</p></section>
      <section id="x"><p id="y">B</p></section>
    </body></html>
    """

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html; charset=utf-8"},
            content=html,
            request=request,
        )

    with _client(handler) as client:
        document = ingest_url_native(
            "https://fixture.example/duplicate-ids",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    paragraphs = [block for block in document.blocks if block.kind == "p"]
    assert [block.text for block in paragraphs] == ["A", "B"]
    assert paragraphs[0].locator == "section#x > p#y"
    assert paragraphs[1].locator == "section#x > p#y::occurrence:2"
    assert len({block.locator for block in document.blocks}) == len(document.blocks)



@pytest.mark.parametrize(
    ("html", "expected_parts"),
    [
        (b"<body>Deadline<hr>Sep 30</body>", ["Deadline", "Sep 30"]),
        (
            b"<body>Deadline<figure>Sep 30</figure>WIB</body>",
            ["Deadline", "Sep 30", "WIB"],
        ),
        (
            b"<body>Deadline<form>Sep 30</form>WIB</body>",
            ["Deadline", "Sep 30", "WIB"],
        ),
        (
            b"<body>Deadline<fieldset>Sep 30</fieldset>WIB</body>",
            ["Deadline", "Sep 30", "WIB"],
        ),
        (
            b"<body>Deadline<table><caption>Sep 30</caption></table>WIB</body>",
            ["Deadline", "Sep 30", "WIB"],
        ),
    ],
)
def test_html_structural_boundaries_do_not_concatenate_visible_text(
    html: bytes,
    expected_parts: list[str],
) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html; charset=utf-8"},
            content=html,
            request=request,
        )

    with _client(handler) as client:
        document = ingest_url_native(
            "https://fixture.example/structural-boundary",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    assert document.text.splitlines() == expected_parts
    assert "DeadlineSep" not in document.text
    assert "Sep 30WIB" not in document.text


def test_locator_suffix_namespace_cannot_collide_with_document_ids() -> None:
    html = b"""
    <html><body>
      <p id="x::occurrence:2">A</p>
      <p id="x">B</p>
      <p id="x">C</p>
    </body></html>
    """

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html; charset=utf-8"},
            content=html,
            request=request,
        )

    with _client(handler) as client:
        document = ingest_url_native(
            "https://fixture.example/adversarial-locator-id",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    paragraphs = [block for block in document.blocks if block.kind == "p"]
    assert [block.text for block in paragraphs] == ["A", "B", "C"]
    assert paragraphs[0].locator == "p#x%3A%3Aoccurrence%3A2"
    assert paragraphs[1].locator == "p#x"
    assert paragraphs[2].locator == "p#x::occurrence:2"
    assert len({block.locator for block in document.blocks}) == len(document.blocks)


def test_hidden_void_separator_does_not_change_visible_text_boundary() -> None:
    html = b"<body>Dead<br hidden><hr hidden>line</body>"

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html; charset=utf-8"},
            content=html,
            request=request,
        )

    with _client(handler) as client:
        document = ingest_url_native(
            "https://fixture.example/hidden-separator",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    assert document.text == "Deadline"

@pytest.mark.parametrize(
    "fake_meta",
    [
        b'<!-- <meta charset="windows-1252"> -->',
        b'<script>const x = \'<meta charset="windows-1252">\';</script>',
    ],
)
def test_fake_meta_charset_in_comment_or_script_does_not_override_utf8(fake_meta: bytes) -> None:
    html = fake_meta + '<p>Café — deadline</p>'.encode()

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html"},
            content=html,
            request=request,
        )

    with _client(handler) as client:
        document = ingest_url_native(
            "https://fixture.example/fake-meta-charset",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    assert document.text == "Café — deadline"


def test_pdf_native_uses_sensible_visual_reading_order() -> None:
    generated = pymupdf.open()
    page = generated.new_page()
    page.insert_text((72, 700), "BOTTOM deadline")
    page.insert_text((72, 72), "TOP organizer")
    pdf = generated.tobytes()
    generated.close()

    document = ingest_pdf_native(
        "upload/visual-order.pdf",
        pdf,
        context=_context("src-pdf-order"),
        retrieved_at=FIXED_TIME,
    )

    texts = [block.text for block in document.blocks]
    assert texts == ["TOP organizer", "BOTTOM deadline"]
    assert document.text.index("TOP organizer") < document.text.index("BOTTOM deadline")


def test_html_native_block_cap_stops_object_amplification() -> None:
    html = b"<body><p>a</p><p>b</p><p>c</p></body>"

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html"},
            content=html,
            request=request,
        )

    from engine.extraction import SourceLimitExceededError

    with _client(handler) as client:
        with pytest.raises(SourceLimitExceededError, match="block limit"):
            ingest_url_native(
                "https://fixture.example/block-cap",
                context=_context(),
                client=client,
                retrieved_at=FIXED_TIME,
                max_native_blocks=2,
            )


def test_html_native_text_cap_stops_extracted_text_amplification() -> None:
    html = b"<body><p>abcdefghij</p></body>"

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html"},
            content=html,
            request=request,
        )

    from engine.extraction import SourceLimitExceededError

    with _client(handler) as client:
        with pytest.raises(SourceLimitExceededError, match="extracted text limit"):
            ingest_url_native(
                "https://fixture.example/text-cap",
                context=_context(),
                client=client,
                retrieved_at=FIXED_TIME,
                max_extracted_text_chars=5,
            )


def test_pdf_native_block_cap_is_enforced() -> None:
    pdf = (FIXTURES / "native_competition.pdf").read_bytes()

    from engine.extraction import SourceLimitExceededError

    with pytest.raises(SourceLimitExceededError, match="block limit"):
        ingest_pdf_native(
            "upload/native_competition.pdf",
            pdf,
            context=_context("src-pdf-block-cap"),
            retrieved_at=FIXED_TIME,
            max_native_blocks=1,
        )


def test_pdf_native_text_cap_is_enforced() -> None:
    pdf = (FIXTURES / "native_competition.pdf").read_bytes()

    from engine.extraction import SourceLimitExceededError

    with pytest.raises(SourceLimitExceededError, match="extracted text limit"):
        ingest_pdf_native(
            "upload/native_competition.pdf",
            pdf,
            context=_context("src-pdf-text-cap"),
            retrieved_at=FIXED_TIME,
            max_extracted_text_chars=10,
        )


def test_https_redirect_to_http_is_rejected() -> None:
    calls: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(str(request.url))
        return httpx.Response(
            302,
            headers={"location": "http://public.example/final"},
            request=request,
        )

    with _client(handler) as client, pytest.raises(SourceFetchError, match="insecure HTTP"):
        ingest_url_native(
            "https://official.example/rules",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    assert calls == ["https://official.example/rules"]


def test_unexpected_http_206_is_rejected_as_incomplete_source() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            206,
            headers={"content-type": "text/html"},
            content=b"<html><body><p>partial</p></body></html>",
            request=request,
        )

    with _client(handler) as client:
        with pytest.raises(SourceFetchError, match="206 Partial Content"):
            ingest_url_native(
                "https://fixture.example/partial",
                context=_context(),
                client=client,
                retrieved_at=FIXED_TIME,
            )


def test_xhtml_is_not_claimed_as_supported_native_media_type() -> None:
    xml = b'<?xml version="1.0" encoding="shift_jis"?><html><body>rules</body></html>'

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "application/xhtml+xml"},
            content=xml,
            request=request,
        )

    with _client(handler) as client:
        with pytest.raises(UnsupportedMediaTypeError, match="application/xhtml\\+xml"):
            ingest_url_native(
                "https://fixture.example/rules.xhtml",
                context=_context(),
                client=client,
                retrieved_at=FIXED_TIME,
            )


def test_svg_text_is_preserved_by_static_native_html_extraction() -> None:
    html = b"<body><svg><text>Deadline Sep 30</text></svg></body>"

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html"},
            content=html,
            request=request,
        )

    with _client(handler) as client:
        document = ingest_url_native(
            "https://fixture.example/svg-text",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    assert "Deadline Sep 30" in document.text
    assert any(block.kind == "text" for block in document.blocks)


def test_button_and_option_text_have_structural_boundaries() -> None:
    html = (
        b"<body><button>Apply</button><button>Rules</button>"
        b"<select><option>A</option><option>B</option></select></body>"
    )

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/html"},
            content=html,
            request=request,
        )

    with _client(handler) as client:
        document = ingest_url_native(
            "https://fixture.example/ui-boundaries",
            context=_context(),
            client=client,
            retrieved_at=FIXED_TIME,
        )

    lines = document.text.splitlines()
    assert lines == ["Apply", "Rules", "A", "B"]
    assert "ApplyRules" not in document.text
    assert "AB" not in document.text




def test_dns_hostname_resolving_to_private_ip_is_rejected_before_network(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[str] = []

    def private_getaddrinfo(
        host: str,
        port: int,
        *args: object,
        **kwargs: object,
    ) -> list[tuple[int, int, int, str, tuple[str, int]]]:
        assert host == "public-looking.example"
        return [
            (
                socket.AF_INET,
                socket.SOCK_STREAM,
                socket.IPPROTO_TCP,
                "",
                ("127.0.0.1", port),
            )
        ]

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(str(request.url))
        return httpx.Response(200, request=request, content=b"should-not-run")

    monkeypatch.setattr(
        "engine.extraction.url_security.socket.getaddrinfo",
        private_getaddrinfo,
    )

    with _client(handler) as client, pytest.raises(
        InvalidSourceError,
        match="resolved to a non-public IP",
    ):
            ingest_url_native(
                "https://public-looking.example/rules",
                context=_context(),
                client=client,
                retrieved_at=FIXED_TIME,
            )

    assert calls == []


def test_dns_mixed_public_and_private_answers_are_rejected(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def mixed_getaddrinfo(
        host: str,
        port: int,
        *args: object,
        **kwargs: object,
    ) -> list[tuple[int, int, int, str, tuple[str, int]]]:
        return [
            (
                socket.AF_INET,
                socket.SOCK_STREAM,
                socket.IPPROTO_TCP,
                "",
                ("93.184.216.34", port),
            ),
            (
                socket.AF_INET,
                socket.SOCK_STREAM,
                socket.IPPROTO_TCP,
                "",
                ("10.0.0.7", port),
            ),
        ]

    monkeypatch.setattr(
        "engine.extraction.url_security.socket.getaddrinfo",
        mixed_getaddrinfo,
    )

    with pytest.raises(InvalidSourceError, match="resolved to a non-public IP"):
        ingest_url_native(
            "https://mixed.example/rules",
            context=_context(),
            retrieved_at=FIXED_TIME,
        )


def test_dns_ipv4_mapped_private_ipv6_answer_is_rejected(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def mapped_getaddrinfo(
        host: str,
        port: int,
        *args: object,
        **kwargs: object,
    ) -> list[tuple[int, int, int, str, tuple[str, int, int, int]]]:
        return [
            (
                socket.AF_INET6,
                socket.SOCK_STREAM,
                socket.IPPROTO_TCP,
                "",
                ("::ffff:127.0.0.1", port, 0, 0),
            )
        ]

    monkeypatch.setattr(
        "engine.extraction.url_security.socket.getaddrinfo",
        mapped_getaddrinfo,
    )

    with pytest.raises(InvalidSourceError, match="resolved to a non-public IP"):
        ingest_url_native(
            "https://mapped.example/rules",
            context=_context(),
            retrieved_at=FIXED_TIME,
        )


def test_redirect_dns_target_is_revalidated_before_second_request(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[str] = []

    def redirect_getaddrinfo(
        host: str,
        port: int,
        *args: object,
        **kwargs: object,
    ) -> list[tuple[int, int, int, str, tuple[str, int]]]:
        ip = "93.184.216.34" if host == "start.example" else "169.254.169.254"
        return [
            (
                socket.AF_INET,
                socket.SOCK_STREAM,
                socket.IPPROTO_TCP,
                "",
                (ip, port),
            )
        ]

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(str(request.url))
        if str(request.url) == "https://start.example/rules":
            return httpx.Response(
                302,
                headers={"location": "https://metadata.example/latest"},
                request=request,
            )
        return httpx.Response(200, request=request, content=b"must-not-be-fetched")

    monkeypatch.setattr(
        "engine.extraction.url_security.socket.getaddrinfo",
        redirect_getaddrinfo,
    )

    with _client(handler) as client:
        with pytest.raises(InvalidSourceError, match="resolved to a non-public IP"):
            ingest_url_native(
                "https://start.example/rules",
                context=_context(),
                client=client,
                retrieved_at=FIXED_TIME,
            )

    assert calls == ["https://start.example/rules"]


def test_dns_resolution_failure_is_normalized_to_source_fetch_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def failing_getaddrinfo(
        host: str,
        port: int,
        *args: object,
        **kwargs: object,
    ) -> list[tuple[int, int, int, str, tuple[str, int]]]:
        raise socket.gaierror(socket.EAI_NONAME, "name not known")

    monkeypatch.setattr(
        "engine.extraction.url_security.socket.getaddrinfo",
        failing_getaddrinfo,
    )

    with pytest.raises(SourceFetchError, match="could not be resolved") as caught:
        ingest_url_native(
            "https://missing-dns.example/rules",
            context=_context(),
            retrieved_at=FIXED_TIME,
        )

    assert caught.value.code == "SOURCE_FETCH_FAILED"
