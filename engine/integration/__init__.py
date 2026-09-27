"""Issue-2 end-to-end orchestration exports."""

from engine.integration.competition_analysis import (
    READINESS_REQUIRED_FIELDS_V1,
    CompetitionAnalysisResult,
    analyze_competition,
    build_canonical_report,
    build_readiness_request,
    resolve_eligibility_scope,
)

__all__ = [
    "READINESS_REQUIRED_FIELDS_V1",
    "CompetitionAnalysisResult",
    "analyze_competition",
    "build_canonical_report",
    "build_readiness_request",
    "resolve_eligibility_scope",
]

from engine.integration.plan_evaluation import (
    PlanEvaluationExecutionError,
    PlanEvaluationIndeterminateError,
    PlanEvaluationInputError,
    PlanEvaluationInvariantError,
    ReportBundleError,
    evaluate_plan,
    planning_cutoff,
    verify_report_bundle,
)

__all__ += [
    "PlanEvaluationExecutionError",
    "PlanEvaluationIndeterminateError",
    "PlanEvaluationInputError",
    "PlanEvaluationInvariantError",
    "ReportBundleError",
    "evaluate_plan",
    "planning_cutoff",
    "verify_report_bundle",
]

from engine.integration.competition_api import (
    AnalysisInvariantError,
    AnalysisReconciliationError,
    analyze_pdf,
    analyze_url,
)

__all__ += [
    "AnalysisInvariantError",
    "AnalysisReconciliationError",
    "analyze_pdf",
    "analyze_url",
]
