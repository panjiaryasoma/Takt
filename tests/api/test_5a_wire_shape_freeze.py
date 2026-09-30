"""Freeze every Issue-4A public API wrapper field for parallel 5A/5B work."""

from typing import get_args

import apps.api.contracts
import packages.contracts as shared_contracts

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
    apps.api.contracts.PlanEvaluateResponseV1: {"planning"},
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


# Shared package models are nested directly inside the public API wire. Freezing
# only apps.api.contracts.ApiModel wrappers is insufficient because a nested
# contract can otherwise drift while every wrapper field name remains intact.
SHARED_PUBLIC_WIRE_FIELDS = {
    shared_contracts.SourceRecord: (
        "source_id",
        "source_type",
        "url_or_document_id",
        "retrieved_at",
        "content_hash",
        "authority_rank",
        "scope",
        "freshness_metadata",
    ),
    shared_contracts.EvidenceSpan: (
        "evidence_id",
        "source_id",
        "page_or_locator",
        "raw_text_or_visual_reference",
        "field_name",
        "extraction_path",
        "extractor_version",
    ),
    shared_contracts.CandidateField: (
        "field_name",
        "raw_value",
        "normalized_value",
        "evidence_ids",
        "extraction_path",
        "confidence",
        "scope",
    ),
    shared_contracts.CandidateExtractionReport: (
        "source_id",
        "extraction_path",
        "fields",
        "evidence",
    ),
    shared_contracts.CanonicalField: (
        "field_name",
        "state",
        "value",
        "normalized_value",
        "candidates",
        "evidence_ids",
    ),
    shared_contracts.CanonicalCompetitionReport: (
        "competition_id",
        "report_version",
        "source_ids",
        "canonical_fields",
        "unresolved_critical_fields",
    ),
    shared_contracts.ReadinessTriage: (
        "status",
        "blocking_reasons",
        "review_items",
        "passed_checks",
        "rule_version",
    ),
    shared_contracts.Task: (
        "task_id",
        "name",
        "mandatory",
        "dependencies",
        "effort_min_minutes",
        "effort_likely_minutes",
        "effort_max_minutes",
        "assumptions",
    ),
    shared_contracts.WorkloadAssumption: ("task_id", "description"),
    shared_contracts.WorkloadInput: ("tasks", "assumptions"),
    shared_contracts.PlanningHorizon: ("start", "end"),
    shared_contracts.PlanningWorkWindow: ("start", "end"),
    shared_contracts.RecurrenceSpec: (
        "rrule",
        "timezone",
        "active_from",
        "active_until",
    ),
    shared_contracts.RecurrenceException: (
        "original_start_at",
        "action",
        "replacement_start_at",
        "replacement_end_at",
    ),
    shared_contracts.PlanningCommitment: (
        "commitment_id",
        "type",
        "start_at",
        "end_at",
        "timezone",
        "recurrence",
        "exceptions",
        "source",
    ),
    shared_contracts.AcceptedCommitment: (
        "accepted_commitment_id",
        "start_at",
        "end_at",
        "source",
    ),
    shared_contracts.PlanningPreferences: (
        "timezone",
        "max_project_minutes_per_day",
        "preferred_focus_minutes",
        "buffer_target_minutes",
    ),
    shared_contracts.AvailabilityInput: (
        "horizon",
        "work_windows",
        "commitments",
        "accepted_commitments",
        "preferences",
    ),
    shared_contracts.AllocationBlock: (
        "task_id",
        "start",
        "end",
        "allocated_minutes",
        "availability_source",
    ),
}

SHARED_PUBLIC_DEFAULTED_FIELDS = {
    shared_contracts.CandidateField: {"confidence"},
    shared_contracts.CandidateExtractionReport: {"fields", "evidence"},
    shared_contracts.CanonicalField: {
        "value",
        "normalized_value",
        "candidates",
        "evidence_ids",
    },
    shared_contracts.CanonicalCompetitionReport: {"unresolved_critical_fields"},
    shared_contracts.WorkloadAssumption: {"task_id"},
    shared_contracts.WorkloadInput: {"assumptions"},
    shared_contracts.RecurrenceSpec: {"active_until"},
    shared_contracts.RecurrenceException: {
        "replacement_start_at",
        "replacement_end_at",
    },
    shared_contracts.PlanningCommitment: {"recurrence", "exceptions"},
    shared_contracts.AvailabilityInput: {
        "work_windows",
        "commitments",
        "accepted_commitments",
    },
}

SHARED_PUBLIC_NULLABLE_FIELDS = {
    shared_contracts.CandidateField: {"confidence"},
    shared_contracts.WorkloadAssumption: {"task_id"},
    shared_contracts.RecurrenceSpec: {"active_until"},
    shared_contracts.RecurrenceException: {
        "replacement_start_at",
        "replacement_end_at",
    },
    shared_contracts.PlanningCommitment: {"recurrence"},
}

PUBLIC_ENUM_VALUES = {
    shared_contracts.ReadinessStatus: (
        "READY_TO_EVALUATE",
        "NEEDS_REVIEW",
        "ELIGIBILITY_BLOCKED",
        "DEADLINE_PASSED",
        "INSUFFICIENT_INFORMATION",
    ),
    shared_contracts.FeasibilityStatus: (
        "FEASIBLE",
        "FEASIBLE_WITH_TRADEOFFS",
        "TIGHT_CAPACITY",
        "NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS",
    ),
    shared_contracts.RecommendationAction: (
        "ACCEPT",
        "CHOOSE_ALTERNATIVE",
        "EDIT_CONSTRAINTS",
        "IGNORE",
    ),
    shared_contracts.CanonicalFieldState: (
        "VERIFIED",
        "SINGLE_SOURCE",
        "CONFLICT",
        "MISSING",
        "UNVERIFIED",
    ),
    shared_contracts.SourceType: (
        "official_rules",
        "official_organizer",
        "official_faq",
        "platform",
        "secondary",
        "derived_fixture",
    ),
    shared_contracts.ExtractionPath: ("native", "ocr", "vision", "manual"),
    shared_contracts.CommitmentType: ("FIXED", "FLEXIBLE"),
    shared_contracts.RecurrenceExceptionAction: ("CANCELLED", "MOVED"),
    shared_contracts.AvailabilityType: (
        "AVAILABLE",
        "FIXED_BUSY",
        "FLEXIBLE_BUSY",
        "ACCEPTED_PROJECT_COMMITMENT",
    ),
}

CRITICAL_DEFAULT_VALUES = {
    (apps.api.contracts.ReadinessContextV1, "selected_scope"): None,
    (apps.api.contracts.ReadinessContextV1, "require_technology_information"): False,
    (apps.api.contracts.EvaluationBasisV1, "planning"): None,
    (apps.api.contracts.RecommendationV1, "alternatives"): (),
    (apps.api.contracts.PublicCandidateV1, "assumptions"): (),
    (apps.api.contracts.RecommendationSetV1, "alternative_candidates"): (),
    (apps.api.contracts.PlanningDecisionV1, "reason_codes"): (),
    (apps.api.contracts.PlanningDecisionV1, "tradeoff_codes"): (),
    (apps.api.contracts.PlanningDecisionV1, "sensitivity_codes"): (),
    (apps.api.contracts.ReevaluationTransitionV1, "change_reasons"): (),
    (apps.api.contracts.CompetitionAnalyzeUrlRequestV1, "previous_report_bundle"): None,
    (apps.api.contracts.CompetitionAnalyzeUrlRequestV1, "prior_source_artifacts"): (),
    (apps.api.contracts.CompetitionAnalyzePdfMetadataV1, "previous_report_bundle"): None,
    (apps.api.contracts.CompetitionAnalyzePdfMetadataV1, "prior_source_artifacts"): (),
    (shared_contracts.CandidateField, "confidence"): None,
    (shared_contracts.CandidateExtractionReport, "fields"): [],
    (shared_contracts.CandidateExtractionReport, "evidence"): [],
    (shared_contracts.CanonicalField, "value"): None,
    (shared_contracts.CanonicalField, "normalized_value"): None,
    (shared_contracts.CanonicalField, "candidates"): [],
    (shared_contracts.CanonicalField, "evidence_ids"): [],
    (shared_contracts.CanonicalCompetitionReport, "unresolved_critical_fields"): [],
    (shared_contracts.WorkloadAssumption, "task_id"): None,
    (shared_contracts.WorkloadInput, "assumptions"): (),
    (shared_contracts.RecurrenceSpec, "active_until"): None,
    (shared_contracts.RecurrenceException, "replacement_start_at"): None,
    (shared_contracts.RecurrenceException, "replacement_end_at"): None,
    (shared_contracts.PlanningCommitment, "recurrence"): None,
    (shared_contracts.PlanningCommitment, "exceptions"): (),
    (shared_contracts.AvailabilityInput, "work_windows"): (),
    (shared_contracts.AvailabilityInput, "commitments"): (),
    (shared_contracts.AvailabilityInput, "accepted_commitments"): (),
}


def _property_schema(model, field_name: str):
    return model.model_json_schema()["properties"][field_name]


def test_nested_shared_public_wire_shape_is_frozen() -> None:
    for model, expected_fields in SHARED_PUBLIC_WIRE_FIELDS.items():
        assert tuple(model.model_fields) == expected_fields

        defaulted = {
            name for name, field in model.model_fields.items() if not field.is_required()
        }
        assert defaulted == SHARED_PUBLIC_DEFAULTED_FIELDS.get(model, set())

        nullable = {
            name
            for name, field in model.model_fields.items()
            if _allows_none(field.annotation)
        }
        assert nullable == SHARED_PUBLIC_NULLABLE_FIELDS.get(model, set())


def test_all_public_wire_enum_values_are_frozen() -> None:
    for enum_type, expected in PUBLIC_ENUM_VALUES.items():
        assert tuple(item.value for item in enum_type) == expected


def test_public_wire_default_values_are_semantically_frozen() -> None:
    for (model, field_name), expected in CRITICAL_DEFAULT_VALUES.items():
        field = model.model_fields[field_name]
        assert not field.is_required()
        assert field.get_default(call_default_factory=True) == expected


def test_public_wire_critical_types_and_constraints_are_frozen() -> None:
    task_id = _property_schema(shared_contracts.Task, "task_id")
    assert task_id["type"] == "string"
    assert task_id["minLength"] == 1

    mandatory = _property_schema(shared_contracts.Task, "mandatory")
    assert mandatory["type"] == "boolean"

    effort = _property_schema(shared_contracts.Task, "effort_likely_minutes")
    assert effort["type"] == "integer"
    assert effort["minimum"] == 0

    work_windows = _property_schema(shared_contracts.AvailabilityInput, "work_windows")
    assert work_windows["type"] == "array"
    assert work_windows["items"]["$ref"].endswith("/PlanningWorkWindow")

    commitment_type = _property_schema(shared_contracts.PlanningCommitment, "type")
    assert commitment_type["$ref"].endswith("/CommitmentType")

    source_type = _property_schema(shared_contracts.SourceRecord, "source_type")
    assert source_type["$ref"].endswith("/SourceType")

    availability_source = _property_schema(
        shared_contracts.AllocationBlock,
        "availability_source",
    )
    assert availability_source["type"] == "string"
    assert availability_source["minLength"] == 1

    allocated = _property_schema(shared_contracts.AllocationBlock, "allocated_minutes")
    assert allocated["type"] == "integer"
    assert allocated["exclusiveMinimum"] == 0

    review_items = _property_schema(shared_contracts.ReadinessTriage, "review_items")
    assert review_items["type"] == "array"
    assert review_items["items"]["type"] == "string"

    daily_limit = _property_schema(
        shared_contracts.PlanningPreferences,
        "max_project_minutes_per_day",
    )
    assert daily_limit["type"] == "integer"
    assert daily_limit["minimum"] == 0
    assert daily_limit["maximum"] == 1440

    report_version = _property_schema(
        shared_contracts.CanonicalCompetitionReport,
        "report_version",
    )
    assert report_version["type"] == "integer"
    assert report_version["minimum"] == 1

    confidence = _property_schema(shared_contracts.CandidateField, "confidence")
    numeric = next(
        item
        for item in confidence["anyOf"]
        if item.get("type") == "number"
    )
    assert numeric["minimum"] == 0.0
    assert numeric["maximum"] == 1.0
