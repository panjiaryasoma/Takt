"""Freeze every Issue-4A public API wrapper field for parallel 5A/5B work."""

from typing import get_args

import apps.api.contracts


PUBLIC_WIRE_FIELDS = {
    apps.api.contracts.CanonicalReportRefV1: (
        "domain_schema_version",
        "competition_id",
        "report_version",
        "reconciliation_policy_version",
        "assembly_policy_version",
        "assembly_material_fingerprint",
        "source_set_fingerprint_version",
        "source_set_fingerprint",
        "wire_fingerprint_version",
        "wire_fingerprint",
    ),
    apps.api.contracts.CanonicalReportBundleV1: ("report", "ref"),
    apps.api.contracts.ReadinessUserContextV1: ("age", "student_status", "country"),
    apps.api.contracts.ReadinessContextV1: (
        "user",
        "selected_scope",
        "require_technology_information",
    ),
    apps.api.contracts.PlanEvaluatePlanningV1: ("workload", "availability"),
    apps.api.contracts.PlanEvaluateRequestV1: ("report_bundle", "readiness_context", "planning"),
    apps.api.contracts.ReportBasisV1: (
        "competition_id",
        "report_version",
        "reconciliation_policy_version",
        "assembly_policy_version",
        "assembly_material_fingerprint",
    ),
    apps.api.contracts.ReadinessBasisV1: (
        "basis_version",
        "basis_fingerprint",
        "projection_version",
        "rule_version",
    ),
    apps.api.contracts.PlanningBasisV1: (
        "basis_version",
        "basis_fingerprint",
        "policy_version",
        "solver_backend",
        "solver_backend_version",
    ),
    apps.api.contracts.EvaluationBasisV1: (
        "version",
        "domain_schema_version",
        "fingerprint",
        "report",
        "readiness",
        "planning",
    ),
    apps.api.contracts.CandidateRefV1: ("evaluation_id", "candidate_id"),
    apps.api.contracts.RecommendedNextWorkV1: (
        "task_id",
        "task_name",
        "start",
        "end",
        "allocated_minutes",
        "availability_source",
    ),
    apps.api.contracts.SuggestedWorkWindowV1: (
        "task_id",
        "start",
        "end",
        "allocated_minutes",
        "availability_source",
    ),
    apps.api.contracts.RecommendationAlternativeV1: (
        "candidate_id",
        "buffer_minutes",
        "recommended_next_work",
        "suggested_windows",
        "tradeoffs",
    ),
    apps.api.contracts.RecommendationAssumptionV1: ("task_id", "description"),
    apps.api.contracts.RecommendationV1: (
        "recommended_candidate_id",
        "recommended_next_work",
        "suggested_windows",
        "alternatives",
        "rationale",
        "tradeoffs",
        "assumptions",
    ),
    apps.api.contracts.PublicCandidateV1: ("ref", "work_blocks", "buffer_minutes", "assumptions"),
    apps.api.contracts.RecommendationTraceV1: (
        "competition_id",
        "report_version",
        "assembly_material_fingerprint",
        "evaluation_basis_fingerprint",
        "planning_basis_fingerprint",
        "planning_policy_version",
    ),
    apps.api.contracts.RecommendationSetV1: (
        "primary_candidate",
        "alternative_candidates",
        "recommendation",
        "trace",
    ),
    apps.api.contracts.PlanningDecisionV1: (
        "feasibility",
        "candidates",
        "allowed_actions",
        "reason_codes",
        "tradeoff_codes",
        "sensitivity_codes",
        "recommendation",
    ),
    apps.api.contracts.PlanEvaluateResponseV1: (
        "evaluation_id",
        "evaluated_at",
        "basis",
        "readiness",
        "planning",
    ),
    apps.api.contracts.PriorReportBasisSnapshotV1: (
        "competition_id",
        "report_version",
        "reconciliation_policy_version",
        "assembly_policy_version",
        "assembly_material_fingerprint",
    ),
    apps.api.contracts.PriorReadinessBasisSnapshotV1: (
        "basis_version",
        "basis_fingerprint",
        "projection_version",
        "rule_version",
    ),
    apps.api.contracts.PriorPlanningBasisSnapshotV1: (
        "basis_version",
        "basis_fingerprint",
        "policy_version",
        "solver_backend",
        "solver_backend_version",
    ),
    apps.api.contracts.PriorEvaluationBasisSnapshotV1: (
        "version",
        "domain_schema_version",
        "fingerprint",
        "report",
        "readiness",
        "planning",
    ),
    apps.api.contracts.PriorEvaluationV1: ("evaluation_id", "basis"),
    apps.api.contracts.PlanReevaluateRequestV1: ("prior", "current"),
    apps.api.contracts.ReevaluationTransitionV1: (
        "kind",
        "prior_evaluation_id",
        "prior_basis_fingerprint",
        "current_basis_fingerprint",
        "prior_evaluation_freshness",
        "change_reasons",
    ),
    apps.api.contracts.PlanReevaluateResponseV1: ("transition", "evaluation"),
    apps.api.contracts.ApiErrorDetailV1: ("path", "message", "code"),
    apps.api.contracts.ApiErrorBodyV1: ("code", "message", "stage", "details"),
    apps.api.contracts.ApiErrorResponseV1: ("error",),
    apps.api.contracts.PlanReevaluateErrorResponseV1: ("error", "transition"),
    apps.api.contracts.SourceMetadataV1: (
        "source_id",
        "source_type",
        "authority_rank",
        "scope",
        "freshness_metadata",
    ),
    apps.api.contracts.ExtractionRunAuditV1: (
        "source_id",
        "snapshot_id",
        "extraction_path",
        "extractor_version",
    ),
    apps.api.contracts.SourceAnalysisArtifactV1: (
        "source",
        "candidate_reports",
        "extraction_runs",
    ),
    apps.api.contracts.CompetitionAnalyzeUrlRequestV1: (
        "competition_id",
        "url",
        "source",
        "previous_report_bundle",
        "prior_source_artifacts",
    ),
    apps.api.contracts.CompetitionAnalyzePdfMetadataV1: (
        "competition_id",
        "document_id",
        "source",
        "previous_report_bundle",
        "prior_source_artifacts",
    ),
    apps.api.contracts.AnalysisProvenanceV1: ("sources", "extraction_runs", "evidence"),
    apps.api.contracts.CompetitionAnalyzeResponseV1: (
        "report_bundle",
        "source_artifacts",
        "provenance",
        "report_changed",
    ),
}


PUBLIC_WIRE_DEFAULTED_FIELDS = {
    apps.api.contracts.CanonicalReportRefV1: {
        "domain_schema_version",
        "reconciliation_policy_version",
        "assembly_policy_version",
        "source_set_fingerprint_version",
        "source_set_fingerprint",
        "wire_fingerprint_version",
    },
    apps.api.contracts.ReadinessUserContextV1: {"age", "student_status", "country"},
    apps.api.contracts.ReadinessContextV1: {"selected_scope", "require_technology_information"},
    apps.api.contracts.ReadinessBasisV1: {"basis_version", "projection_version"},
    apps.api.contracts.PlanningBasisV1: {"basis_version", "policy_version", "solver_backend"},
    apps.api.contracts.EvaluationBasisV1: {"version", "domain_schema_version", "planning"},
    apps.api.contracts.RecommendationAssumptionV1: {"task_id"},
    apps.api.contracts.RecommendationV1: {"alternatives"},
    apps.api.contracts.PublicCandidateV1: {"assumptions"},
    apps.api.contracts.RecommendationTraceV1: {"planning_policy_version"},
    apps.api.contracts.RecommendationSetV1: {"alternative_candidates"},
    apps.api.contracts.PlanningDecisionV1: {
        "reason_codes",
        "tradeoff_codes",
        "sensitivity_codes",
    },
    apps.api.contracts.PriorEvaluationBasisSnapshotV1: {"planning"},
    apps.api.contracts.ReevaluationTransitionV1: {"change_reasons"},
    apps.api.contracts.ApiErrorBodyV1: {"details"},
    apps.api.contracts.CompetitionAnalyzeUrlRequestV1: {
        "previous_report_bundle",
        "prior_source_artifacts",
    },
    apps.api.contracts.CompetitionAnalyzePdfMetadataV1: {
        "previous_report_bundle",
        "prior_source_artifacts",
    },
}

PUBLIC_WIRE_NULLABLE_FIELDS = {
    apps.api.contracts.CanonicalReportRefV1: {"source_set_fingerprint"},
    apps.api.contracts.ReadinessUserContextV1: {"age", "student_status", "country"},
    apps.api.contracts.ReadinessContextV1: {"selected_scope"},
    apps.api.contracts.EvaluationBasisV1: {"planning"},
    apps.api.contracts.RecommendationAlternativeV1: {"recommended_next_work"},
    apps.api.contracts.RecommendationAssumptionV1: {"task_id"},
    apps.api.contracts.RecommendationV1: {"recommended_next_work"},
    apps.api.contracts.PlanningDecisionV1: {"recommendation"},
    apps.api.contracts.PriorEvaluationBasisSnapshotV1: {"planning"},
    apps.api.contracts.ReevaluationTransitionV1: {"current_basis_fingerprint"},
    apps.api.contracts.PlanReevaluateResponseV1: {"evaluation"},
    apps.api.contracts.PlanReevaluateErrorResponseV1: {"transition"},
    apps.api.contracts.CompetitionAnalyzeUrlRequestV1: {"previous_report_bundle"},
    apps.api.contracts.CompetitionAnalyzePdfMetadataV1: {"previous_report_bundle"},
}


def _allows_none(annotation) -> bool:
    return type(None) in get_args(annotation)


def test_public_wire_requiredness_and_nullability_are_frozen() -> None:
    for model in PUBLIC_WIRE_FIELDS:
        defaulted = {
            name for name, field in model.model_fields.items() if not field.is_required()
        }
        assert defaulted == PUBLIC_WIRE_DEFAULTED_FIELDS.get(model, set())

        nullable = {
            name
            for name, field in model.model_fields.items()
            if _allows_none(field.annotation)
        }
        assert nullable == PUBLIC_WIRE_NULLABLE_FIELDS.get(model, set())


def test_all_public_api_wrapper_field_sets_are_frozen() -> None:
    public_models = {
        model
        for name, model in vars(apps.api.contracts).items()
        if isinstance(model, type)
        and issubclass(model, apps.api.contracts.ApiModel)
        and model is not apps.api.contracts.ApiModel
        and model.__module__ == apps.api.contracts.__name__
    }
    assert set(PUBLIC_WIRE_FIELDS) == public_models

    for model, expected_fields in PUBLIC_WIRE_FIELDS.items():
        assert tuple(model.model_fields) == expected_fields
