from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError

from apps.api.errors import (
    ApiContractError,
    api_contract_error_handler,
    request_validation_error_handler,
    unhandled_error_handler,
)
from apps.api.routes.competitions import router as competitions_router
from apps.api.routes.health import router as health_router
from apps.api.routes.plans import router as plans_router
from apps.api.routes.triage import router as triage_router

app = FastAPI(
    title="Takt API",
    version="0.1.0",
    description="Calendar-aware competition decision-support backend.",
)

app.add_exception_handler(RequestValidationError, request_validation_error_handler)
app.add_exception_handler(ApiContractError, api_contract_error_handler)
app.add_exception_handler(Exception, unhandled_error_handler)

app.include_router(health_router)
app.include_router(competitions_router, prefix="/api/v1")
app.include_router(triage_router, prefix="/api/v1")
app.include_router(plans_router, prefix="/api/v1")
