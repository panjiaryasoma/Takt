"""Thin Block 4d orchestration from snapshot observations to readiness triage.

This module deliberately does not re-implement extraction, reconciliation,
canonical assembly, or triage semantics. It only composes the already-frozen
boundaries and projects canonical field states into the existing Issue-1
ReadinessRequest contract.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any, Iterable

from pydantic import ValidationError

from engine.extraction import (
    SnapshotExtractionResult,
    derive_snapshot_source_ids,
)
from engine.reconciliation import (
    CANONICAL_V1,
    CanonicalReportAssemblyResult,
    assemble_canonical_report,
    reconcile_field,
)
from engine.triage.scope import ResolvedEligibilityScope
from engine.triage.service import evaluate_readiness
from packages.contracts import (
    CanonicalCompetitionReport,
    CanonicalField,
    CanonicalFieldState,
    EligibilityRule,
    ReadinessRequest,
    ReadinessTriage,
    UserContext,
)

READINESS_REQUIRED_FIELDS_V1 = (
    "submission_deadline",
    "eligibility",
    "deliverables",
)

_USABLE_STATES = frozenset(
    {
        CanonicalFieldState.VERIFIED,
        CanonicalFieldState.SINGLE_SOURCE,
    }
)
_REVIEW_STATES = frozenset(
    {
        CanonicalFieldState.CONFLICT,
        CanonicalFieldState.UNVERIFIED,
    }
)
_SCOPE_WILDCARDS = frozenset({"*", "all", "any"})
_ELIGIBILITY_RULE_KEYS = frozenset(
    {"minimum_age", "requires_student", "allowed_regions"}
)
_SCOPED_WRAPPER_KEYS = frozenset({"variants"})
_SCOPED_VARIANT_KEYS = frozenset({"scope", "value"})
_SCOPE_KEYS = frozenset({"audience", "category", "region"})


@dataclass(frozen=True, slots=True)
class CompetitionAnalysisResult:
    """Audit-friendly result of the Block 4d orchestration boundary."""

    canonical_assembly: CanonicalReportAssemblyResult
    readiness_request: ReadinessRequest
    resolved_eligibility_scope: ResolvedEligibilityScope | None
    readiness: ReadinessTriage

    @property
    def canonical_report(self) -> CanonicalCompetitionReport:
        return self.canonical_assembly.report

    @property
    def field_results(self):
        return self.canonical_assembly.field_results


def _snapshot_results_tuple(
    results: Iterable[SnapshotExtractionResult],
) -> tuple[SnapshotExtractionResult, ...]:
    if isinstance(results, (str, bytes)):
        raise TypeError("snapshot_results must be an iterable of extraction results")
    try:
        items = tuple(results)
    except TypeError as exc:
        raise TypeError("snapshot_results must be iterable") from exc
    return items


def build_canonical_report(
    *,
    competition_id: str,
    snapshot_results: Iterable[SnapshotExtractionResult],
    previous_report: CanonicalCompetitionReport | None = None,
) -> CanonicalReportAssemblyResult:
    """Compose 4c -> 4a -> 4b without inventing new field semantics."""

    results = _snapshot_results_tuple(snapshot_results)
    snapshot_source_ids = derive_snapshot_source_ids(results)
    candidate_reports = tuple(
        report
        for result in results
        for report in result.candidate_reports
    )
    source_records = tuple(result.snapshot.source_record for result in results)

    field_results = tuple(
        reconcile_field(
            field_name,
            reports=candidate_reports,
            sources=source_records,
        )
        for field_name in CANONICAL_V1.core_fields
    )

    return assemble_canonical_report(
        competition_id=competition_id,
        field_results=field_results,
        snapshot_source_ids=snapshot_source_ids,
        previous_report=previous_report,
        policy=CANONICAL_V1,
    )


def _revalidate_canonical_report(
    report: CanonicalCompetitionReport,
) -> CanonicalCompetitionReport:
    if not isinstance(report, CanonicalCompetitionReport):
        raise TypeError("canonical_report must be CanonicalCompetitionReport")
    return CanonicalCompetitionReport.model_validate(
        report.model_dump(mode="python")
    )


def _revalidate_user(user: UserContext) -> UserContext:
    if not isinstance(user, UserContext):
        raise TypeError("user must be UserContext")
    return UserContext.model_validate(user.model_dump(mode="python"))


def _validate_technology_requirement_flag(value: bool) -> bool:
    if type(value) is not bool:
        raise TypeError("require_technology_information must be bool")
    return value


def _canonical_field(
    report: CanonicalCompetitionReport,
    field_name: str,
) -> CanonicalField:
    return report.canonical_fields[field_name]


def _normalized_scope_token(value: str) -> str:
    return value.strip().lower()


def _scope_aliases(scope: Any) -> frozenset[str]:
    if not isinstance(scope, dict):
        return frozenset()

    concrete: list[tuple[str, str]] = []
    for key in ("audience", "category", "region"):
        raw_value = scope.get(key)
        if not isinstance(raw_value, str):
            continue
        value = _normalized_scope_token(raw_value)
        if not value or value in _SCOPE_WILDCARDS:
            continue
        concrete.append((key, value))

    # A single selected_scope string can safely encode exactly one concrete
    # applicability dimension. Multi-dimensional variants require a richer
    # selector and therefore stay unresolved in readiness-v1.
    if len(concrete) != 1:
        return frozenset()

    key, value = concrete[0]
    return frozenset(
        {
            value,
            f"{key}:{value}",
            f"{value}_{key}",
        }
    )


def _eligibility_payload(field: CanonicalField) -> Any:
    if field.normalized_value is not None:
        return field.normalized_value
    return field.value


def _as_eligibility_rule(value: Any) -> EligibilityRule | None:
    if not isinstance(value, dict) or set(value) != _ELIGIBILITY_RULE_KEYS:
        return None

    minimum_age = value["minimum_age"]
    if minimum_age is not None:
        if type(minimum_age) is not int or minimum_age < 0:
            return None

    requires_student = value["requires_student"]
    if type(requires_student) is not bool:
        return None

    allowed_regions = value["allowed_regions"]
    if not isinstance(allowed_regions, list):
        return None
    if any(
        type(region) is not str or not region.strip()
        for region in allowed_regions
    ):
        return None

    try:
        return EligibilityRule.model_validate(
            {
                "minimum_age": minimum_age,
                "requires_student": requires_student,
                "allowed_regions": allowed_regions,
            }
        )
    except (TypeError, ValueError, ValidationError):
        return None


def _strict_scope_material(value: Any) -> dict[str, str | None] | None:
    if not isinstance(value, dict) or set(value) != _SCOPE_KEYS:
        return None

    normalized: dict[str, str | None] = {}
    for key in ("audience", "category", "region"):
        item = value[key]
        if item is None:
            normalized[key] = None
            continue
        if type(item) is not str or not item.strip():
            return None
        normalized[key] = item.strip()
    return normalized


def _eligibility_provenance(
    field: CanonicalField,
    *,
    selected_scope: str,
    scope_material: Any | None = None,
) -> tuple[str, ...]:
    trace = [
        "canonical_field:eligibility",
        f"selected_scope:{selected_scope}",
    ]
    if scope_material is not None:
        trace.append(
            "effective_scope:"
            + json.dumps(
                scope_material,
                sort_keys=True,
                ensure_ascii=False,
                separators=(",", ":"),
            )
        )
    trace.extend(f"evidence:{item}" for item in sorted(field.evidence_ids))
    return tuple(trace)


def _resolve_eligibility_scope_validated(
    *,
    canonical_report: CanonicalCompetitionReport,
    selected_scope: str | None,
) -> ResolvedEligibilityScope | None:
    field = _canonical_field(canonical_report, "eligibility")
    if field.state not in _USABLE_STATES:
        return None
    if not isinstance(selected_scope, str) or not selected_scope.strip():
        return None

    requested_scope = _normalized_scope_token(selected_scope)
    payload = _eligibility_payload(field)

    if not isinstance(payload, dict):
        return None

    if "variants" not in payload:
        if requested_scope != "unscoped":
            return None
        rule = _as_eligibility_rule(payload)
        if rule is None:
            return None
        return ResolvedEligibilityScope(
            selected_scope="unscoped",
            effective_rule=rule,
            provenance=_eligibility_provenance(
                field,
                selected_scope="unscoped",
            ),
        )

    if set(payload) != _SCOPED_WRAPPER_KEYS:
        return None
    raw_variants = payload["variants"]
    if not isinstance(raw_variants, list) or not raw_variants:
        return None

    parsed_variants: list[tuple[dict[str, str | None], EligibilityRule]] = []
    for raw_variant in raw_variants:
        if not isinstance(raw_variant, dict):
            return None
        if set(raw_variant) != _SCOPED_VARIANT_KEYS:
            return None
        scope = _strict_scope_material(raw_variant["scope"])
        if scope is None:
            return None
        rule = _as_eligibility_rule(raw_variant["value"])
        if rule is None:
            return None
        parsed_variants.append((scope, rule))

    matches = [
        (scope, rule)
        for scope, rule in parsed_variants
        if requested_scope in _scope_aliases(scope)
    ]
    if len(matches) != 1:
        return None

    scope, rule = matches[0]
    return ResolvedEligibilityScope(
        selected_scope=selected_scope.strip(),
        effective_rule=rule,
        provenance=_eligibility_provenance(
            field,
            selected_scope=selected_scope.strip(),
            scope_material=scope,
        ),
    )


def resolve_eligibility_scope(
    *,
    canonical_report: CanonicalCompetitionReport,
    selected_scope: str | None,
) -> ResolvedEligibilityScope | None:
    """Resolve strict readiness-v1 eligibility from canonical material only."""

    validated_report = _revalidate_canonical_report(canonical_report)
    return _resolve_eligibility_scope_validated(
        canonical_report=validated_report,
        selected_scope=selected_scope,
    )


def _canonical_deadline(field: CanonicalField) -> datetime | None:
    if field.state not in _USABLE_STATES:
        return None

    value = field.normalized_value
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        cleaned = value.strip()
        if "T" not in cleaned:
            return None
        try:
            parsed = datetime.fromisoformat(cleaned.replace("Z", "+00:00"))
        except ValueError:
            return None
    else:
        return None

    if parsed.tzinfo is None or parsed.utcoffset() is None:
        return None
    return parsed.astimezone(UTC)


def _append_unique(target: list[str], field_name: str) -> None:
    if field_name not in target:
        target.append(field_name)


def _project_field_state(
    *,
    field: CanonicalField,
    field_name: str,
    mandatory_missing: list[str],
    unresolved: list[str],
) -> None:
    if field.state is CanonicalFieldState.MISSING:
        _append_unique(mandatory_missing, field_name)
        return
    if field.state in _REVIEW_STATES:
        _append_unique(unresolved, field_name)


def _build_readiness_projection(
    *,
    canonical_report: CanonicalCompetitionReport,
    user: UserContext,
    selected_scope: str | None,
    evaluated_at: datetime,
    require_technology_information: bool,
) -> tuple[ReadinessRequest, ResolvedEligibilityScope | None]:
    canonical_report = _revalidate_canonical_report(canonical_report)
    user = _revalidate_user(user)
    require_technology_information = _validate_technology_requirement_flag(
        require_technology_information
    )

    mandatory_missing: list[str] = []
    unresolved: list[str] = []

    deadline_field = _canonical_field(canonical_report, "submission_deadline")
    _project_field_state(
        field=deadline_field,
        field_name="submission_deadline",
        mandatory_missing=mandatory_missing,
        unresolved=unresolved,
    )
    deadline = _canonical_deadline(deadline_field)
    if deadline_field.state in _USABLE_STATES and deadline is None:
        _append_unique(unresolved, "submission_deadline")

    eligibility_field = _canonical_field(canonical_report, "eligibility")
    _project_field_state(
        field=eligibility_field,
        field_name="eligibility",
        mandatory_missing=mandatory_missing,
        unresolved=unresolved,
    )

    resolved_scope: ResolvedEligibilityScope | None = None
    effective_rule = EligibilityRule()
    if eligibility_field.state in _USABLE_STATES:
        resolved_scope = _resolve_eligibility_scope_validated(
            canonical_report=canonical_report,
            selected_scope=selected_scope,
        )
        if resolved_scope is None:
            _append_unique(unresolved, "eligibility")
        else:
            effective_rule = resolved_scope.effective_rule.model_copy(deep=True)

    deliverables_field = _canonical_field(canonical_report, "deliverables")
    _project_field_state(
        field=deliverables_field,
        field_name="deliverables",
        mandatory_missing=mandatory_missing,
        unresolved=unresolved,
    )

    if require_technology_information:
        technologies = _canonical_field(canonical_report, "required_technologies")
        _project_field_state(
            field=technologies,
            field_name="required_technologies",
            mandatory_missing=mandatory_missing,
            unresolved=unresolved,
        )

    request = ReadinessRequest(
        evaluated_at=evaluated_at,
        submission_deadline=deadline,
        has_applicable_deadline_extension=False,
        eligibility=effective_rule,
        user=user.model_copy(deep=True),
        unresolved_critical_fields=unresolved,
        mandatory_information_complete=not mandatory_missing,
    )
    return request, resolved_scope


def build_readiness_request(
    *,
    canonical_report: CanonicalCompetitionReport,
    user: UserContext,
    selected_scope: str | None,
    evaluated_at: datetime,
    require_technology_information: bool = False,
) -> ReadinessRequest:
    """Project canonical states into the frozen Issue-1 ReadinessRequest.

    ``CanonicalCompetitionReport.unresolved_critical_fields`` is intentionally
    not copied. MISSING mandatory facts map to incomplete information, while
    CONFLICT/UNVERIFIED readiness facts map to the triage unresolved list.
    """

    request, _ = _build_readiness_projection(
        canonical_report=canonical_report,
        user=user,
        selected_scope=selected_scope,
        evaluated_at=evaluated_at,
        require_technology_information=require_technology_information,
    )
    return request


def analyze_competition(
    *,
    competition_id: str,
    snapshot_results: Iterable[SnapshotExtractionResult],
    user: UserContext,
    selected_scope: str | None,
    evaluated_at: datetime,
    require_technology_information: bool = False,
    previous_report: CanonicalCompetitionReport | None = None,
) -> CompetitionAnalysisResult:
    """Run the final Issue-2 glue path and invoke the frozen Issue-1 triage."""

    assembly = build_canonical_report(
        competition_id=competition_id,
        snapshot_results=snapshot_results,
        previous_report=previous_report,
    )
    request, resolved_scope = _build_readiness_projection(
        canonical_report=assembly.report,
        user=user,
        selected_scope=selected_scope,
        evaluated_at=evaluated_at,
        require_technology_information=require_technology_information,
    )
    readiness = evaluate_readiness(request)
    return CompetitionAnalysisResult(
        canonical_assembly=assembly,
        readiness_request=request,
        resolved_eligibility_scope=resolved_scope,
        readiness=readiness,
    )
