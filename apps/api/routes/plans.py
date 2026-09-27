"""Product plan-evaluation API route."""

from fastapi import APIRouter

from apps.api.contracts import (
    ApiErrorResponseV1,
    PlanEvaluateRequestV1,
    PlanEvaluateResponseV1,
)
from apps.api.errors import ApiContractError
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
    evaluate_plan,
)

router = APIRouter(tags=["plans"])

_PLAN_ERROR_RESPONSES = {
    422: {"model": ApiErrorResponseV1},
    500: {"model": ApiErrorResponseV1},
    503: {"model": ApiErrorResponseV1},
}


@router.post(
    "/plans/evaluate",
    response_model=PlanEvaluateResponseV1,
    responses=_PLAN_ERROR_RESPONSES,
)
def evaluate_plan_route(request: PlanEvaluateRequestV1) -> PlanEvaluateResponseV1:
    try:
        return evaluate_plan(request)
    except UnsupportedReportContractError as exc:
        raise ApiContractError(
            status_code=422,
            code="UNSUPPORTED_REPORT_CONTRACT",
            message="Canonical report contract or policy version is not supported.",
            stage="report",
        ) from exc
    except ReportBundleError as exc:
        raise ApiContractError(
            status_code=422,
            code="REPORT_BUNDLE_INVALID",
            message="Canonical report bundle failed integrity validation.",
            stage="report",
        ) from exc
    except PlanEvaluationInputError as exc:
        raise ApiContractError(
            status_code=422,
            code="PLANNING_INPUT_INVALID",
            message="Evaluation input cannot be used by the planning pipeline.",
            stage="evaluation",
        ) from exc
    except PlanEvaluationIndeterminateError as exc:
        raise ApiContractError(
            status_code=503,
            code="SOLVER_INDETERMINATE",
            message="The solver could not determine a planning result.",
            stage="solver",
        ) from exc
    except PlanEvaluationAvailabilityError as exc:
        raise ApiContractError(
            status_code=500,
            code="AVAILABILITY_EXECUTION_FAILED",
            message="Availability preparation could not complete.",
            stage="availability",
        ) from exc
    except PlanEvaluationSolverExecutionError as exc:
        raise ApiContractError(
            status_code=500,
            code="SOLVER_EXECUTION_FAILED",
            message="The solver could not complete execution.",
            stage="solver",
        ) from exc
    except PlanEvaluationRuntimeError as exc:
        raise ApiContractError(
            status_code=500,
            code="PLANNING_RUNTIME_UNAVAILABLE",
            message="A required planning runtime dependency is unavailable.",
            stage="planning",
        ) from exc
    except PlanEvaluationExecutionError as exc:
        raise ApiContractError(
            status_code=500,
            code="PLANNING_EXECUTION_FAILED",
            message="The planning pipeline could not complete execution.",
            stage="planning",
        ) from exc
    except PlanEvaluationInvariantError as exc:
        raise ApiContractError(
            status_code=500,
            code="EVALUATION_INVARIANT_FAILED",
            message="The server produced inconsistent evaluation artifacts.",
            stage="evaluation",
        ) from exc
