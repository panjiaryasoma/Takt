"""Stable public error envelopes and FastAPI exception handlers."""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass

from fastapi import Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from apps.api.contracts import (
    ApiErrorBodyV1,
    ApiErrorDetailV1,
    ApiErrorResponseV1,
    PlanReevaluateErrorResponseV1,
    ReevaluationTransitionV1,
)
from apps.api.services.plan_evaluation import (
    PlanEvaluationAvailabilityError,
    PlanEvaluationExecutionError,
    PlanEvaluationIndeterminateError,
    PlanEvaluationInputError,
    PlanEvaluationInvariantError,
    PlanEvaluationRuntimeError,
    PlanEvaluationSolverExecutionError,
    ReportBundleError,
    UnsupportedReportContractError,
)


class ApiContractError(Exception):
    """Intentional public API failure with stable machine-readable semantics."""

    def __init__(
        self,
        *,
        status_code: int,
        code: str,
        message: str,
        stage: str,
        details: Iterable[ApiErrorDetailV1] = (),
    ) -> None:
        super().__init__(code)
        self.status_code = status_code
        self.code = code
        self.public_message = message
        self.stage = stage
        self.details = tuple(details)


class PlanReevaluateContractError(ApiContractError):
    """Public re-evaluation failure with optional trusted stale transition."""

    def __init__(
        self,
        *,
        status_code: int,
        code: str,
        message: str,
        stage: str,
        transition: ReevaluationTransitionV1 | None,
        details: Iterable[ApiErrorDetailV1] = (),
    ) -> None:
        super().__init__(
            status_code=status_code,
            code=code,
            message=message,
            stage=stage,
            details=details,
        )
        self.transition = transition


@dataclass(frozen=True, slots=True)
class PlanFailureContract:
    status_code: int
    code: str
    message: str
    stage: str


def classify_plan_failure(exc: Exception) -> PlanFailureContract:
    if isinstance(exc, UnsupportedReportContractError):
        return PlanFailureContract(
            422,
            "UNSUPPORTED_REPORT_CONTRACT",
            "Canonical report contract or policy version is not supported.",
            "report",
        )
    if isinstance(exc, ReportBundleError):
        return PlanFailureContract(
            422,
            "REPORT_BUNDLE_INVALID",
            "Canonical report bundle failed integrity validation.",
            "report",
        )
    if isinstance(exc, PlanEvaluationInputError):
        return PlanFailureContract(
            422,
            "PLANNING_INPUT_INVALID",
            "Evaluation input cannot be used by the planning pipeline.",
            "evaluation",
        )
    if isinstance(exc, PlanEvaluationIndeterminateError):
        return PlanFailureContract(
            503,
            "SOLVER_INDETERMINATE",
            "The solver could not determine a planning result.",
            "solver",
        )
    if isinstance(exc, PlanEvaluationAvailabilityError):
        return PlanFailureContract(
            500,
            "AVAILABILITY_EXECUTION_FAILED",
            "Availability preparation could not complete.",
            "availability",
        )
    if isinstance(exc, PlanEvaluationSolverExecutionError):
        return PlanFailureContract(
            500,
            "SOLVER_EXECUTION_FAILED",
            "The solver could not complete execution.",
            "solver",
        )
    if isinstance(exc, PlanEvaluationRuntimeError):
        return PlanFailureContract(
            500,
            "PLANNING_RUNTIME_UNAVAILABLE",
            "A required planning runtime dependency is unavailable.",
            "planning",
        )
    if isinstance(exc, PlanEvaluationExecutionError):
        return PlanFailureContract(
            500,
            "PLANNING_EXECUTION_FAILED",
            "The planning pipeline could not complete execution.",
            "planning",
        )
    if isinstance(exc, PlanEvaluationInvariantError):
        return PlanFailureContract(
            500,
            "EVALUATION_INVARIANT_FAILED",
            "The server produced inconsistent evaluation artifacts.",
            "evaluation",
        )
    return PlanFailureContract(
        500,
        "INTERNAL_ERROR",
        "The server could not complete the request.",
        "internal",
    )


def _clean_loc(loc: tuple[object, ...]) -> tuple[object, ...]:
    parts = tuple(loc)
    if parts and parts[0] in {"body", "query", "path", "header", "cookie"}:
        return parts[1:]
    return parts


def json_pointer(loc: tuple[object, ...]) -> str:
    parts = _clean_loc(loc)
    if not parts:
        return "/"
    encoded = [
        str(item).replace("~", "~0").replace("/", "~1")
        for item in parts
    ]
    return "/" + "/".join(encoded)


def _public_validation_detail_code(error_type: object) -> str:
    value = str(error_type or "")
    if value == "missing":
        return "REQUIRED"
    if value == "extra_forbidden":
        return "UNKNOWN_FIELD"
    if (
        value.endswith("_type")
        or value in {
            "bool_parsing",
            "date_parsing",
            "datetime_parsing",
            "float_parsing",
            "int_parsing",
            "string_type",
        }
    ):
        return "INVALID_TYPE"
    return "INVALID_VALUE"


def validation_details(
    errors: Iterable[dict[str, object]],
) -> tuple[ApiErrorDetailV1, ...]:
    return tuple(
        ApiErrorDetailV1(
            path=json_pointer(tuple(item.get("loc", ()))),
            message=str(item.get("msg", "Invalid value.")),
            code=_public_validation_detail_code(item.get("type")),
        )
        for item in errors
    )


def validation_contract(
    errors: Iterable[dict[str, object]],
    *,
    request_path: str,
) -> tuple[str, str, str]:
    items = tuple(errors)
    types = {str(item.get("type", "")) for item in items}
    if "unsupported_reevaluation_contract" in types:
        return (
            "UNSUPPORTED_REEVALUATION_CONTRACT",
            "Prior evaluation basis structural version is not supported.",
            "reevaluation",
        )
    if "unsupported_report_contract" in types:
        return (
            "UNSUPPORTED_REPORT_CONTRACT",
            "Canonical report contract or policy version is not supported.",
            "report",
        )
    if "report_bundle_invalid" in types:
        return (
            "REPORT_BUNDLE_INVALID",
            "Canonical report bundle failed integrity validation.",
            "report",
        )

    if request_path.startswith("/api/v1/competitions/analyze/") and items:
        locations = [_clean_loc(tuple(item.get("loc", ()))) for item in items]
        if all(location and location[0] == "source" for location in locations):
            return (
                "SOURCE_METADATA_INVALID",
                "Source metadata validation failed.",
                "ingestion",
            )

    return ("VALIDATION_ERROR", "Request validation failed.", "validation")


def _api_payload(
    *,
    code: str,
    message: str,
    stage: str,
    details: tuple[ApiErrorDetailV1, ...] = (),
) -> ApiErrorBodyV1:
    return ApiErrorBodyV1(
        code=code,
        message=message,
        stage=stage,
        details=details,
    )


def _response(
    *,
    status_code: int,
    code: str,
    message: str,
    stage: str,
    details: tuple[ApiErrorDetailV1, ...] = (),
) -> JSONResponse:
    payload = ApiErrorResponseV1(
        error=_api_payload(
            code=code,
            message=message,
            stage=stage,
            details=details,
        )
    )
    return JSONResponse(
        status_code=status_code,
        content=payload.model_dump(mode="json", warnings=False),
    )


def _reevaluation_response(
    *,
    status_code: int,
    code: str,
    message: str,
    stage: str,
    transition: ReevaluationTransitionV1 | None,
    details: tuple[ApiErrorDetailV1, ...] = (),
) -> JSONResponse:
    payload = PlanReevaluateErrorResponseV1(
        error=_api_payload(
            code=code,
            message=message,
            stage=stage,
            details=details,
        ),
        transition=transition,
    )
    return JSONResponse(
        status_code=status_code,
        content=payload.model_dump(mode="json", warnings=False),
    )


async def api_contract_error_handler(
    request: Request,
    exc: ApiContractError,
) -> JSONResponse:
    del request
    return _response(
        status_code=exc.status_code,
        code=exc.code,
        message=exc.public_message,
        stage=exc.stage,
        details=exc.details,
    )


async def reevaluation_contract_error_handler(
    request: Request,
    exc: PlanReevaluateContractError,
) -> JSONResponse:
    del request
    return _reevaluation_response(
        status_code=exc.status_code,
        code=exc.code,
        message=exc.public_message,
        stage=exc.stage,
        transition=exc.transition,
        details=exc.details,
    )


async def request_validation_error_handler(
    request: Request,
    exc: RequestValidationError,
) -> JSONResponse:
    if request.url.path == "/api/v1/triage":
        return JSONResponse(
            status_code=422,
            content=jsonable_encoder({"detail": exc.errors()}),
        )

    errors = tuple(exc.errors())
    code, message, stage = validation_contract(
        errors,
        request_path=request.url.path,
    )
    details = validation_details(errors)
    if request.url.path == "/api/v1/plans/re-evaluate":
        return _reevaluation_response(
            status_code=422,
            code=code,
            message=message,
            stage=stage,
            transition=None,
            details=details,
        )
    return _response(
        status_code=422,
        code=code,
        message=message,
        stage=stage,
        details=details,
    )


async def unhandled_error_handler(
    request: Request,
    exc: Exception,
) -> JSONResponse:
    del exc
    if request.url.path == "/api/v1/plans/re-evaluate":
        return _reevaluation_response(
            status_code=500,
            code="INTERNAL_ERROR",
            message="The server could not complete the request.",
            stage="internal",
            transition=None,
        )
    return _response(
        status_code=500,
        code="INTERNAL_ERROR",
        message="The server could not complete the request.",
        stage="internal",
    )
