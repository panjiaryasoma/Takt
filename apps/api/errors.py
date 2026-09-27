"""Stable public error envelope and FastAPI exception handlers."""

from __future__ import annotations

from collections.abc import Iterable

from fastapi import Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from apps.api.contracts import (
    ApiErrorBodyV1,
    ApiErrorDetailV1,
    ApiErrorResponseV1,
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


def _response(
    *,
    status_code: int,
    code: str,
    message: str,
    stage: str,
    details: tuple[ApiErrorDetailV1, ...] = (),
) -> JSONResponse:
    payload = ApiErrorResponseV1(
        error=ApiErrorBodyV1(
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
    return _response(
        status_code=422,
        code=code,
        message=message,
        stage=stage,
        details=validation_details(errors),
    )


async def unhandled_error_handler(
    request: Request,
    exc: Exception,
) -> JSONResponse:
    del request, exc
    return _response(
        status_code=500,
        code="INTERNAL_ERROR",
        message="The server could not complete the request.",
        stage="internal",
    )
