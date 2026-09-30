"""Small adapters over existing API fixtures and the 5A error authority."""

from datetime import timedelta

import httpx
import pymupdf

from apps.api.contracts import CompetitionAnalyzePdfMetadataV1, ReadinessUserContextV1
from engine.extraction import SourceContext
from packages.contracts import CanonicalField, CanonicalFieldState, WorkloadInput
from tests.api.test_competition_analysis_behavior import (
    _source as source_metadata,
)
from tests.api.test_competition_analysis_behavior import (
    _url_request,
)
from tests.api.test_plan_evaluate_behavior import (
    _bundle,
    _candidate_field,
    _review_report,
)
from tests.api.test_plan_evaluate_behavior import (
    _clock as clock,
)
from tests.api.test_plan_evaluate_behavior import (
    _request as plan_request,
)
from tests.support.public_error_matrix import PUBLIC_ERROR_MATRIX, TRANSITION_NA

url_request = _url_request

PRIVATE_SENTINEL = "private-6a-provider-detail-token"
URL_ENDPOINT = "POST /api/v1/competitions/analyze/url"
PDF_ENDPOINT = "POST /api/v1/competitions/analyze/pdf"
PLAN_ENDPOINT = "POST /api/v1/plans/evaluate"
REEVALUATE_ENDPOINT = "POST /api/v1/plans/re-evaluate"


def contract_case(endpoint, failure_class):
    matches = [
        row
        for row in PUBLIC_ERROR_MATRIX
        if (row.endpoint, row.failure_class) == (endpoint, failure_class)
    ]
    assert len(matches) == 1
    return matches[0]


def assert_public_failure(response, endpoint, failure_class, *, transition=None):
    case = contract_case(endpoint, failure_class)
    assert response.status_code == case.http_status
    body = response.json()
    assert set(body) == ({"error"} if case.transition == TRANSITION_NA else {"error", "transition"})
    assert set(body["error"]) == {"code", "message", "stage", "details"}
    assert body["error"]["code"] == case.code
    assert body["error"]["stage"] == case.stage
    assert isinstance(body["error"]["message"], str)
    assert body["error"]["message"]
    assert isinstance(body["error"]["details"], list)
    for detail in body["error"]["details"]:
        assert set(detail) == {"path", "message", "code"}
        assert all(isinstance(value, str) and value for value in detail.values())
    if case.transition != TRANSITION_NA:
        assert body["transition"] == transition
    assert PRIVATE_SENTINEL not in response.text
    assert "Traceback" not in response.text
    return body


def source_context():
    source = source_metadata()
    return SourceContext(**source.model_dump(mode="python"))


def pdf_metadata():
    return CompetitionAnalyzePdfMetadataV1(
        competition_id="cmp-6a",
        document_id="reliability.pdf",
        source=source_metadata(),
    )


def pdf_bytes(*, pages=1, text="Nothing relevant here", image_only=False):
    with pymupdf.open() as document:
        for _ in range(pages):
            page = document.new_page(width=320, height=200)
            if image_only:
                pixmap = pymupdf.Pixmap(pymupdf.csRGB, (0, 0, 8, 8), False)
                pixmap.clear_with(200)
                page.insert_image(page.rect, pixmap=pixmap)
            elif text:
                page.insert_text((20, 40), text)
        return document.tobytes()


class EmptyOCR:
    provider_id = "6a-empty-success"
    provider_version = "1"
    language = "eng"
    page_segmentation_mode = 6

    def extract_page(self, image_bytes, *, page_number, timeout_seconds):
        return ()


def mock_source_client(content, media_type="text/html", *, requests=None):
    def respond(request):
        if requests is not None:
            requests.append(request)
        return httpx.Response(
            200, content=content, headers={"content-type": media_type}, request=request
        )

    return httpx.Client(transport=httpx.MockTransport(respond))


def public_dns(*_args, **_kwargs):
    return [(2, 1, 6, "", ("93.184.216.34", 443))]


def domain_request(scenario_id):
    request = plan_request(effort_minutes=60)
    report = request.report_bundle.report
    fields = dict(report.canonical_fields)
    if scenario_id == "DEADLINE_PASSED":
        deadline = clock().replace(second=0) - timedelta(minutes=1)
        fields["submission_deadline"] = _candidate_field(
            "submission_deadline",
            value=deadline.isoformat(),
            normalized=deadline,
        )
    elif scenario_id in {"FAILED_ELIGIBILITY", "UNKNOWN_USER_ATTRIBUTE"}:
        fields["eligibility"] = _candidate_field(
            "eligibility",
            value="Minimum age: 18",
            normalized={
                "minimum_age": 18,
                "requires_student": False,
                "allowed_regions": ["global"],
            },
        )
        request = request.model_copy(
            update={
                "readiness_context": request.readiness_context.model_copy(
                    update={
                        "user": ReadinessUserContextV1(
                            age=17 if scenario_id == "FAILED_ELIGIBILITY" else None
                        )
                    }
                )
            }
        )
    elif scenario_id == "CRITICAL_CONFLICT":
        report = _review_report(deadline=fields["submission_deadline"].normalized_value)
        fields = dict(report.canonical_fields)
    elif scenario_id == "MISSING_MANDATORY_INFORMATION":
        fields["deliverables"] = CanonicalField(
            field_name="deliverables",
            state=CanonicalFieldState.MISSING,
        )
    elif scenario_id == "ZERO_USABLE_AVAILABILITY":
        return request.model_copy(
            update={
                "planning": request.planning.model_copy(
                    update={
                        "availability": request.planning.availability.model_copy(
                            update={"work_windows": ()}
                        ),
                    }
                )
            }
        )
    elif scenario_id == "NARROW_CAPACITY":
        task = request.planning.workload.tasks[0].model_copy(
            update={
                "effort_min_minutes": 30,
                "effort_max_minutes": 200,
            }
        )
        return request.model_copy(
            update={
                "planning": request.planning.model_copy(
                    update={
                        "workload": WorkloadInput(tasks=(task,)),
                    }
                )
            }
        )
    elif scenario_id == "SOLVER_INFEASIBLE":
        return plan_request(effort_minutes=200)
    else:
        raise KeyError(scenario_id)
    return request.model_copy(
        update={
            "report_bundle": _bundle(
                report.model_copy(update={"canonical_fields": fields}),
            )
        }
    )
