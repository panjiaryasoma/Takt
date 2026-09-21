from fastapi import APIRouter

from engine.triage.service import evaluate_readiness
from packages.contracts.triage import ReadinessRequest, ReadinessResponse

router = APIRouter(tags=["triage"])


@router.post("/triage", response_model=ReadinessResponse)
def triage(request: ReadinessRequest) -> ReadinessResponse:
    return evaluate_readiness(request)
