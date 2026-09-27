"""Stable public error envelope and FastAPI exception handlers."""

from __future__ import annotations

from collections.abc import Iterable

from fastapi import Request
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


def _json_pointer(loc: tuple[object, ...]) -> str:
    parts = list(loc)
    if parts and parts[0] in {"body", "query", "path", "header", "cookie"}:
        parts = parts[1:]
    if not parts:
        return "/"

    encoded = []
    for item in parts:
        token = str(item).replace("~", "~0").replace("/", "~1")
        encoded.append(token)
    return "/" + "/".join(encoded)


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
    del request
    details = tuple(
        ApiErrorDetailV1(
            path=_json_pointer(tuple(item.get("loc", ()))),
            message=str(item.get("msg", "Invalid value.")),
            type=str(item.get("type")) if item.get("type") else None,
        )
        for item in exc.errors()
    )
    return _response(
        status_code=422,
        code="VALIDATION_ERROR",
        message="Request validation failed.",
        stage="validation",
        details=details,
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
