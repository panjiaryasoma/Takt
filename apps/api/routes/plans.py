"""Product plan-evaluation and re-evaluation API routes."""

from fastapi import APIRouter

from apps.api.contracts import (
    ApiErrorResponseV1,
    PlanEvaluateRequestV1,
    PlanEvaluateResponseV1,
    PlanReevaluateErrorResponseV1,
    PlanReevaluateRequestV1,
    PlanReevaluateResponseV1,
)
from apps.api.errors import (
    ApiContractError,
    PlanReevaluateContractError,
    classify_plan_failure,
)
from apps.api.services.plan_evaluation import evaluate_plan
from apps.api.services.reevaluation import (
    ReevaluationContextInvalid,
    ReevaluationExecutionFailure,
    reevaluate_plan,
)

router = APIRouter(tags=["plans"])

_PLAN_ERROR_RESPONSES = {
    422: {"model": ApiErrorResponseV1},
    500: {"model": ApiErrorResponseV1},
    503: {"model": ApiErrorResponseV1},
}

_REEVALUATE_ERROR_RESPONSES = {
    409: {"model": PlanReevaluateErrorResponseV1},
    422: {"model": PlanReevaluateErrorResponseV1},
    500: {"model": PlanReevaluateErrorResponseV1},
    503: {"model": PlanReevaluateErrorResponseV1},
}


@router.post(
    "/plans/evaluate",
    response_model=PlanEvaluateResponseV1,
    responses=_PLAN_ERROR_RESPONSES,
)
def evaluate_plan_route(request: PlanEvaluateRequestV1) -> PlanEvaluateResponseV1:
    try:
        return evaluate_plan(request)
    except Exception as exc:
        contract = classify_plan_failure(exc)
        raise ApiContractError(
            status_code=contract.status_code,
            code=contract.code,
            message=contract.message,
            stage=contract.stage,
        ) from exc


@router.post(
    "/plans/re-evaluate",
    response_model=PlanReevaluateResponseV1,
    responses=_REEVALUATE_ERROR_RESPONSES,
)
def reevaluate_plan_route(
    request: PlanReevaluateRequestV1,
) -> PlanReevaluateResponseV1:
    try:
        return reevaluate_plan(request)
    except ReevaluationContextInvalid as exc:
        raise PlanReevaluateContractError(
            status_code=409,
            code="REEVALUATION_CONTEXT_INVALID",
            message="Prior and current evaluation context cannot be compared safely.",
            stage="reevaluation",
            transition=None,
        ) from exc
    except ReevaluationExecutionFailure as exc:
        contract = classify_plan_failure(exc.cause)
        raise PlanReevaluateContractError(
            status_code=contract.status_code,
            code=contract.code,
            message=contract.message,
            stage=contract.stage,
            transition=exc.transition,
        ) from exc
