"""7A: a single extraction path must not silently select contradictory facts."""

from dataclasses import replace

import pytest
from fastapi.testclient import TestClient

import apps.api.routes.competitions as route
from apps.api.main import app
from apps.api.services.competition_analysis import analyze_pdf, analyze_url
from engine.extraction.candidate_bridge import normalize_candidate_report
from engine.extraction.errors import CandidateNormalizationError
from engine.extraction.models import NativeDocument, NativeTextBlock
from engine.extraction.ocr.models import OCRTextBlock
from tests.api.test_competition_analysis_behavior import _pdf_bytes
from tests.extraction.test_ocr import _semantic_ocr_document
from tests.reliability.support import (
    PDF_ENDPOINT,
    URL_ENDPOINT,
    EmptyOCR,
    assert_public_failure,
    mock_source_client,
    pdf_metadata,
    public_dns,
    url_request,
)

DEADLINES = (
    "Submission deadline: September 30 2026 at 23:59 WIB",
    "Submission deadline: October 1 2026 at 23:59 WIB",
)
TEAM_SIZES = ("Team size: 1 to 4 members", "Team size: 2 to 6 members")


def _document(path, layout, statements):
    texts = statements if layout == "blocks" else [layout.join(statements)]
    ocr = replace(
        _semantic_ocr_document(),
        blocks=tuple(
            OCRTextBlock(locator=f"page:1:line:{i}", text=text, page_number=1)
            for i, text in enumerate(texts)
        ),
    )
    if path == "ocr":
        return ocr
    return NativeDocument(
        source_record=ocr.source_record,
        media_type="application/pdf",
        raw_size_bytes=100,
        blocks=tuple(
            NativeTextBlock(locator=block.locator, text=block.text, kind="text")
            for block in ocr.blocks
        ),
    )


@pytest.mark.parametrize("path", ["native", "ocr"])
@pytest.mark.parametrize("layout", ["blocks", "\n", "; "])
@pytest.mark.parametrize("statements", [
    DEADLINES,
    TEAM_SIZES,
    (DEADLINES[0], "Submission deadline: October 1 2026 at 23:59 UTC+07:00"),
    (TEAM_SIZES[0], "Team size: TBD"),
])
def test_contradictory_labeled_facts_fail_closed_in_either_order(path, layout, statements):
    for ordered in (statements, statements[::-1]):
        with pytest.raises(CandidateNormalizationError, match="conflicting"):
            normalize_candidate_report(_document(path, layout, ordered))


@pytest.mark.parametrize("path", ["native", "ocr"])
@pytest.mark.parametrize("layout", ["blocks", "\n", "; "])
@pytest.mark.parametrize(
    "statements",
    [
        (DEADLINES[0], DEADLINES[0]),
        (TEAM_SIZES[0], TEAM_SIZES[0]),
        (DEADLINES[0], "Submission deadline: September 30 2026 at 16:59 UTC"),
    ],
)
def test_repeated_agreeing_facts_keep_one_resolvable_candidate(path, layout, statements):
    document = _document(path, layout, statements)
    report = normalize_candidate_report(document)
    assert len(report.fields) == len(report.evidence) == 1
    assert report.fields[0].evidence_ids == [report.evidence[0].evidence_id]
    assert report.evidence[0].page_or_locator in {block.locator for block in document.blocks}


def test_devpost_rules_metadata_produces_core_candidates():
    report = normalize_candidate_report(
        _document(
            "native",
            "blocks",
            [
                "Nebius x NVIDIA Global AI Hackathon (the “Hackathon”) Official Rules",
                "Deadline: Oct 30, 2026 @ 10:00am PDT",
                (
                    "Sponsor: Nebius B.V., Schiphol Boulevard 165, "
                    "1118 BG Schiphol, the Netherlands"
                ),
            ],
        )
    )

    fields = {field.field_name: field for field in report.fields}
    assert fields["competition_name"].normalized_value == (
        "Nebius x NVIDIA Global AI Hackathon"
    )
    assert fields["organizer"].normalized_value == "Nebius B.V."
    assert fields["submission_deadline"].normalized_value == (
        "2026-10-30T10:00:00-07:00"
    )


@pytest.mark.parametrize("path", ["native", "ocr"])
@pytest.mark.parametrize("zone", ["UTC+07:00", "GMT+7", "UTC +07:00", "WIBB"])
def test_unsupported_timezone_must_not_be_truncated_into_a_known_zone(path, zone):
    report = normalize_candidate_report(_document(
        path, "blocks", [f"Submission deadline: September 30 2026 at 23:59 {zone}"]
    ))
    assert report.fields == []
    assert report.evidence == []


@pytest.mark.parametrize("path", ["native", "ocr"])
@pytest.mark.parametrize(
    "statement",
    [
        "Submission deadline: September 30 2026 at 23:59 WIB or October 1 2026 at 23:59 WIB",
        "Team size: 1 to 4 or 2 to 6",
        "Submission deadline: September 30 2026 at 23:59 WIB / October 1 2026 at 23:59 WIB",
        "Team size: 1 to 4 / 2 to 6",
    ],
)
def test_one_label_with_conflicting_alternatives_fails_closed(path, statement):
    with pytest.raises(CandidateNormalizationError, match="conflicting"):
        normalize_candidate_report(_document(path, "blocks", [statement]))


@pytest.mark.parametrize("path", ["native", "ocr"])
@pytest.mark.parametrize(
    "statement",
    [
        "Submission deadline: September 30 2026 at 23:59 WIB or October 1 2026 at 23:59 UTC+07:00",
        "Team size: 1 to 4 or TBD",
    ],
)
def test_one_label_mixed_supported_and_unsupported_alternatives_fails_closed(
    path, statement
):
    with pytest.raises(CandidateNormalizationError, match="conflicting"):
        normalize_candidate_report(_document(path, "blocks", [statement]))


@pytest.mark.parametrize("path", ["native", "ocr"])
@pytest.mark.parametrize(
    "statement",
    [
        "Submission deadline: September 30 2026 at 23:59 WIB or September 30 2026 at 16:59 UTC",
        "Team size: 1 to 4 or 1 to 4",
    ],
)
def test_one_label_agreeing_alternatives_keep_one_candidate(path, statement):
    report = normalize_candidate_report(_document(path, "blocks", [statement]))
    assert len(report.fields) == len(report.evidence) == 1


@pytest.mark.parametrize("path", ["native", "ocr"])
@pytest.mark.parametrize(
    "statement",
    [
        "Submission deadline: September 30 2026 at 23:59 WIB; October 1 2026 at 23:59 WIB",
        "Submission deadline: September 30 2026 at 23:59 WIB and October 1 2026 at 23:59 WIB",
        "Team size: 1 to 4; 2 to 6",
        "Team size: 1 to 4 and 2 to 6",
    ],
)
def test_trailing_supported_value_cannot_hide_after_first_match(path, statement):
    with pytest.raises(CandidateNormalizationError, match="conflicting"):
        normalize_candidate_report(_document(path, "blocks", [statement]))


@pytest.mark.parametrize("path", ["native", "ocr"])
@pytest.mark.parametrize(
    "statement",
    [
        "Submission deadline: September 30 2026 at 23:59 WIB; October 1 2026 at 25:99 WIB",
        "Team size: 1 to 4; 6 to 2",
    ],
)
def test_trailing_invalid_fact_cannot_be_ignored_after_supported_value(path, statement):
    with pytest.raises(CandidateNormalizationError, match="conflicting"):
        normalize_candidate_report(_document(path, "blocks", [statement]))


@pytest.mark.parametrize("path", ["native", "ocr"])
def test_unsupported_explicit_deadline_time_cannot_downgrade_to_date_only(path):
    with pytest.raises(CandidateNormalizationError, match="conflicting"):
        normalize_candidate_report(_document(
            path, "blocks", ["Submission deadline: September 30 2026 at TBD"]
        ))


@pytest.mark.parametrize("path", ["native", "ocr"])
@pytest.mark.parametrize(
    "statement",
    [
        "Submission deadline: TBD; September 30 2026 at 23:59 WIB",
        "Team size: TBD 1 to 4",
    ],
)
def test_unsupported_prefix_cannot_authorize_a_later_supported_value(path, statement):
    report = normalize_candidate_report(_document(path, "blocks", [statement]))
    assert report.fields == []
    assert report.evidence == []


@pytest.mark.parametrize("endpoint", [URL_ENDPOINT, PDF_ENDPOINT])
def test_ambiguous_source_uses_existing_public_failure_contract(monkeypatch, endpoint):
    monkeypatch.setattr("socket.getaddrinfo", public_dns)
    html = "<html>" + "".join(f"<p>{text}</p>" for text in DEADLINES) + "</html>"
    with mock_source_client(html.encode()) as source_client, TestClient(app) as client:
        if endpoint == URL_ENDPOINT:
            monkeypatch.setattr(route, "analyze_url", lambda req: analyze_url(req, client=source_client))
            response = client.post(endpoint.split()[1], json=url_request().model_dump(mode="json"))
        else:
            monkeypatch.setattr(
                route, "analyze_pdf", lambda metadata, content: analyze_pdf(
                    metadata, content, ocr_provider=EmptyOCR()
                )
            )
            response = client.post(
                endpoint.split()[1],
                data={"metadata": pdf_metadata().model_dump_json()},
                files={"file": ("ambiguous.pdf", _pdf_bytes("\n".join(DEADLINES)), "application/pdf")},
            )
    assert_public_failure(response, endpoint, "CandidateNormalizationError")
    assert "report_bundle" not in response.json()
    assert DEADLINES[0] not in response.text
