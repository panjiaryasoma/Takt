from fastapi import FastAPI

from apps.api.routes.health import router as health_router
from apps.api.routes.triage import router as triage_router

app = FastAPI(
    title="Takt API",
    version="0.1.0",
    description="Calendar-aware competition decision-support backend.",
)

app.include_router(health_router)
app.include_router(triage_router, prefix="/api/v1")
