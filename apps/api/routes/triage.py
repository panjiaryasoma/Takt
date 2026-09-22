from fastapi import APIRouter

from engine.triage.service import evaluate_readiness
from packages.contracts.models import ReadinessTriage
from packages.contracts.triage import ReadinessRequest

router = APIRouter(tags=["triage"])


@router.post("/triage", response_model=ReadinessTriage)
def triage(request: ReadinessRequest) -> ReadinessTriage:
    return evaluate_readiness(request)
