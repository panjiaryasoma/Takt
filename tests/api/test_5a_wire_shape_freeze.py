"""Freeze every Issue-4A public API wrapper field for parallel 5A/5B work."""

from __future__ import annotations

import apps.api.contracts as wire


PUBLIC_WIRE_FIELDS = {
    wire.CanonicalReportRefV1: (
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
    wire.CanonicalReportBundleV1: ("report", "ref"),
    wire.ReadinessUserContextV1: ("age", "student_status", "country"),
    wire.ReadinessContextV1: (
        "user",
        "selected_scope",
        "require_technology_information",
    ),
    wire.PlanEvaluatePlanningV1: ("workload", "availability"),
    wire.PlanEvaluateRequestV1: ("report_bundle", "readiness_context", "planning"),
    wire.ReportBasisV1: (
        "competition_id",
        "report_version",
        "reconciliation_policy_version",
        "assembly_policy_version",
        "assembly_material_fingerprint",
    ),
    wire.ReadinessBasisV1: (
        "basis_version",
        "basis_fingerprint",
        "projection_version",
        "rule_version",
    ),
    wire.PlanningBasisV1: (
        "basis_version",
        "basis_fingerprint",
        "policy_version",
        "solver_backend",
        "solver_backend_version",
    ),
    wire.EvaluationBasisV1: (
        "version",
        "domain_schema_version",
        "fingerprint",
        "report",
        "readiness",
        "planning",
    ),
    wire.CandidateRefV1: ("evaluation_id", "candidate_id"),
    wire.RecommendedNextWorkV1: (
        "task_id",
        "task_name",
        "start",
        "end",
        "allocated_minutes",
        "availability_source",
    ),
    wire.SuggestedWorkWindowV1: (
        "task_id",
        "start",
        "end",
        "allocated_minutes",
        "availability_source",
    ),
    wire.RecommendationAlternativeV1: (
        "candidate_id",
        "buffer_minutes",
        "recommended_next_work",
        "suggested_windows",
        "tradeoffs",
    ),
    wire.RecommendationAssumptionV1: ("task_id", "description"),
    wire.RecommendationV1: (
        "recommended_candidate_id",
        "recommended_next_work",
        "suggested_windows",
        "alternatives",
        "rationale",
        "tradeoffs",
        "assumptions",
    ),
    wire.PublicCandidateV1: ("ref", "work_blocks", "buffer_minutes", "assumptions"),
    wire.RecommendationTraceV1: (
        "competition_id",
        "report_version",
        "assembly_material_fingerprint",
        "evaluation_basis_fingerprint",
        "planning_basis_fingerprint",
        "planning_policy_version",
    ),
    wire.RecommendationSetV1: (
        "primary_candidate",
        "alternative_candidates",
        "recommendation",
        "trace",
    ),
    wire.PlanningDecisionV1: (
        "feasibility",
        "candidates",
        "allowed_actions",
        "reason_codes",
        "tradeoff_codes",
        "sensitivity_codes",
        "recommendation",
    ),
    wire.PlanEvaluateResponseV1: (
        "evaluation_id",
        "evaluated_at",
        "basis",
        "readiness",
        "planning",
    ),
    wire.PriorReportBasisSnapshotV1: (
        "competition_id",
        "report_version",
        "reconciliation_policy_version",
        "assembly_policy_version",
        "assembly_material_fingerprint",
    ),
    wire.PriorReadinessBasisSnapshotV1: (
        "basis_version",
        "basis_fingerprint",
        "projection_version",
        "rule_version",
    ),
    wire.PriorPlanningBasisSnapshotV1: (
        "basis_version",
        "basis_fingerprint",
        "policy_version",
        "solver_backend",
        "solver_backend_version",
    ),
    wire.PriorEvaluationBasisSnapshotV1: (
        "version",
        "domain_schema_version",
        "fingerprint",
        "report",
        "readiness",
        "planning",
    ),
    wire.PriorEvaluationV1: ("evaluation_id", "basis"),
    wire.PlanReevaluateRequestV1: ("prior", "current"),
    wire.ReevaluationTransitionV1: (
        "kind",
        "prior_evaluation_id",
        "prior_basis_fingerprint",
        "current_basis_fingerprint",
        "prior_evaluation_freshness",
        "change_reasons",
    ),
    wire.PlanReevaluateResponseV1: ("transition", "evaluation"),
    wire.ApiErrorDetailV1: ("path", "message", "code"),
    wire.ApiErrorBodyV1: ("code", "message", "stage", "details"),
    wire.ApiErrorResponseV1: ("error",),
    wire.PlanReevaluateErrorResponseV1: ("error", "transition"),
    wire.SourceMetadataV1: (
        "source_id",
        "source_type",
        "authority_rank",
        "scope",
        "freshness_metadata",
    ),
    wire.ExtractionRunAuditV1: (
        "source_id",
        "snapshot_id",
        "extraction_path",
        "extractor_version",
    ),
    wire.SourceAnalysisArtifactV1: (
        "source",
        "candidate_reports",
        "extraction_runs",
    ),
    wire.CompetitionAnalyzeUrlRequestV1: (
        "competition_id",
        "url",
        "source",
        "previous_report_bundle",
        "prior_source_artifacts",
    ),
    wire.CompetitionAnalyzePdfMetadataV1: (
        "competition_id",
        "document_id",
        "source",
        "previous_report_bundle",
        "prior_source_artifacts",
    ),
    wire.AnalysisProvenanceV1: ("sources", "extraction_runs", "evidence"),
    wire.CompetitionAnalyzeResponseV1: (
        "report_bundle",
        "source_artifacts",
        "provenance",
        "report_changed",
    ),
}


def test_all_public_api_wrapper_field_sets_are_frozen() -> None:
    public_models = {
        model
        for name, model in vars(wire).items()
        if isinstance(model, type)
        and issubclass(model, wire.ApiModel)
        and model is not wire.ApiModel
        and model.__module__ == wire.__name__
    }
    assert set(PUBLIC_WIRE_FIELDS) == public_models

    for model, expected_fields in PUBLIC_WIRE_FIELDS.items():
        assert tuple(model.model_fields) == expected_fields
