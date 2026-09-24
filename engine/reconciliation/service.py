"""Pure canonical report assembly and material-change versioning."""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from datetime import date, datetime
from enum import Enum
from hashlib import sha256
from typing import Any, Iterable

from pydantic import BaseModel, ValidationError

from engine.reconciliation.assembly_policy import (
    CANONICAL_V1,
    CanonicalAssemblyPolicy,
)
from engine.reconciliation.models import (
    FieldReconciliationResult,
    ReconciliationInputError,
)
from packages.contracts import (
    CanonicalCompetitionReport,
    CanonicalField,
)
from packages.contracts.source import UNRESOLVED_CANONICAL_STATES


@dataclass(frozen=True, slots=True)
class CanonicalReportAssemblyResult:
    """Canonical report plus deterministic assembly audit trace."""

    report: CanonicalCompetitionReport
    field_results: tuple[FieldReconciliationResult, ...]
    report_changed: bool
    assembly_policy_version: str
    material_fingerprint: str


def _validate_competition_id(competition_id: str) -> str:
    if not isinstance(competition_id, str) or not competition_id.strip():
        raise ReconciliationInputError("competition_id must be a non-empty string")
    return competition_id.strip()


def _normalize_snapshot_source_ids(source_ids: Iterable[str]) -> tuple[str, ...]:
    if isinstance(source_ids, (str, bytes)):
        raise ReconciliationInputError(
            "snapshot_source_ids must be an iterable of source IDs, not a string"
        )

    normalized: set[str] = set()
    try:
        iterator = iter(source_ids)
    except TypeError as exc:
        raise ReconciliationInputError(
            "snapshot_source_ids must be iterable"
        ) from exc

    for source_id in iterator:
        if not isinstance(source_id, str) or not source_id.strip():
            raise ReconciliationInputError(
                "snapshot_source_ids must contain non-empty strings"
            )
        normalized.add(source_id.strip())

    if not normalized:
        raise ReconciliationInputError("snapshot_source_ids must not be empty")
    return tuple(sorted(normalized))


def _revalidate_canonical_field(field: CanonicalField) -> CanonicalField:
    try:
        payload = field.model_dump(mode="python")
        return CanonicalField.model_validate(payload)
    except (AttributeError, TypeError, ValueError, ValidationError) as exc:
        raise ReconciliationInputError(
            "field reconciliation result violates canonical field contract"
        ) from exc


def _copy_field_result(result: FieldReconciliationResult) -> FieldReconciliationResult:
    if not isinstance(result, FieldReconciliationResult):
        raise ReconciliationInputError(
            "field_results must contain FieldReconciliationResult values"
        )

    canonical_field = _revalidate_canonical_field(result.canonical_field)

    try:
        resolution_basis = tuple(result.resolution_basis)
        supporting_source_ids = tuple(result.supporting_source_ids)
        superseded_source_ids = tuple(result.superseded_source_ids)
    except TypeError as exc:
        raise ReconciliationInputError(
            "field reconciliation trace must be iterable"
        ) from exc

    trace_strings = (
        *resolution_basis,
        *supporting_source_ids,
        *superseded_source_ids,
    )
    if any(not isinstance(item, str) for item in trace_strings):
        raise ReconciliationInputError(
            "field reconciliation trace must contain strings"
        )

    return FieldReconciliationResult(
        canonical_field=canonical_field.model_copy(deep=True),
        resolution_basis=resolution_basis,
        supporting_source_ids=supporting_source_ids,
        superseded_source_ids=superseded_source_ids,
    )


def _validate_and_order_field_results(
    field_results: Iterable[FieldReconciliationResult],
    snapshot_source_ids: tuple[str, ...],
    policy: CanonicalAssemblyPolicy,
) -> tuple[FieldReconciliationResult, ...]:
    if isinstance(field_results, (str, bytes)):
        raise ReconciliationInputError(
            "field_results must be an iterable of reconciliation results"
        )

    snapshot_set = set(snapshot_source_ids)
    by_field: dict[str, FieldReconciliationResult] = {}

    try:
        iterator = iter(field_results)
    except TypeError as exc:
        raise ReconciliationInputError("field_results must be iterable") from exc

    for raw_result in iterator:
        result = _copy_field_result(raw_result)
        field_name = result.canonical_field.field_name

        if field_name not in policy.core_fields:
            raise ReconciliationInputError(
                f"unknown canonical field result: {field_name!r}"
            )
        if field_name in by_field:
            raise ReconciliationInputError(
                f"duplicate FieldReconciliationResult for {field_name!r}"
            )

        trace_source_ids = set(result.supporting_source_ids)
        trace_source_ids.update(result.superseded_source_ids)
        unknown_trace_sources = trace_source_ids.difference(snapshot_set)
        if unknown_trace_sources:
            names = ", ".join(sorted(unknown_trace_sources))
            raise ReconciliationInputError(
                "field reconciliation trace references source outside snapshot: "
                f"{names}"
            )

        by_field[field_name] = result

    missing_fields = [
        field_name for field_name in policy.core_fields if field_name not in by_field
    ]
    if missing_fields:
        names = ", ".join(missing_fields)
        raise ReconciliationInputError(
            f"incomplete reconciliation batch; missing field results: {names}"
        )

    return tuple(by_field[field_name] for field_name in policy.core_fields)


def _derive_unresolved_critical_fields(
    field_results: tuple[FieldReconciliationResult, ...],
    policy: CanonicalAssemblyPolicy,
) -> tuple[str, ...]:
    by_field = {
        result.canonical_field.field_name: result.canonical_field
        for result in field_results
    }
    return tuple(
        field_name
        for field_name in policy.critical_fields
        if by_field[field_name].state in UNRESOLVED_CANONICAL_STATES
    )


def _canonicalize_material(value: Any) -> Any:
    if value is None or isinstance(value, (bool, int, str)):
        return value
    if isinstance(value, float):
        if math.isnan(value):
            return {"__float__": "nan"}
        if math.isinf(value):
            token = "inf" if value > 0 else "-inf"
            return {"__float__": token}
        return value
    if isinstance(value, datetime):
        return {"__datetime__": value.isoformat()}
    if isinstance(value, date):
        return {"__date__": value.isoformat()}
    if isinstance(value, Enum):
        return _canonicalize_material(value.value)
    if isinstance(value, BaseModel):
        return _canonicalize_material(value.model_dump(mode="python"))
    if isinstance(value, dict):
        items = [
            (
                _canonicalize_material(key),
                _canonicalize_material(item),
            )
            for key, item in value.items()
        ]
        items.sort(key=lambda item: _stable_json(item[0]))
        return {"__dict__": items}
    if isinstance(value, (set, frozenset)):
        items = [_canonicalize_material(item) for item in value]
        return {"__set__": sorted(items, key=_stable_json)}
    if isinstance(value, tuple):
        return {"__tuple__": [_canonicalize_material(item) for item in value]}
    if isinstance(value, list):
        return [_canonicalize_material(item) for item in value]
    raise ReconciliationInputError(
        f"unsupported canonical material type: {type(value).__name__}"
    )


def _stable_json(value: Any) -> str:
    return json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    )


def _material_payload(report: CanonicalCompetitionReport) -> dict[str, Any]:
    return {
        "competition_id": report.competition_id,
        "source_ids": sorted(report.source_ids),
        "canonical_fields": report.canonical_fields,
        "unresolved_critical_fields": list(report.unresolved_critical_fields),
    }


def material_fingerprint(report: CanonicalCompetitionReport) -> str:
    """Hash canonical report material while excluding report_version."""

    validated = _revalidate_report(report)
    canonical = _canonicalize_material(_material_payload(validated))
    encoded = _stable_json(canonical).encode("utf-8")
    return sha256(encoded).hexdigest()


def _build_report(
    *,
    competition_id: str,
    report_version: int,
    snapshot_source_ids: tuple[str, ...],
    field_results: tuple[FieldReconciliationResult, ...],
    unresolved_critical_fields: tuple[str, ...],
) -> CanonicalCompetitionReport:
    canonical_fields = {
        result.canonical_field.field_name: result.canonical_field.model_dump(
            mode="python"
        )
        for result in field_results
    }
    payload = {
        "competition_id": competition_id,
        "report_version": report_version,
        "source_ids": list(snapshot_source_ids),
        "canonical_fields": canonical_fields,
        "unresolved_critical_fields": list(unresolved_critical_fields),
    }
    try:
        return CanonicalCompetitionReport.model_validate(payload)
    except ValidationError as exc:
        raise ReconciliationInputError(
            "canonical assembly output violates report contract"
        ) from exc


def _revalidate_report(
    report: CanonicalCompetitionReport,
) -> CanonicalCompetitionReport:
    if not isinstance(report, CanonicalCompetitionReport):
        raise ReconciliationInputError(
            "canonical report input must be a CanonicalCompetitionReport"
        )
    try:
        payload = report.model_dump(mode="python")
        return CanonicalCompetitionReport.model_validate(payload)
    except (AttributeError, TypeError, ValueError, ValidationError) as exc:
        raise ReconciliationInputError(
            "canonical report input violates canonical report contract"
        ) from exc


def assemble_canonical_report(
    *,
    competition_id: str,
    field_results: Iterable[FieldReconciliationResult],
    snapshot_source_ids: Iterable[str],
    previous_report: CanonicalCompetitionReport | None = None,
    policy: CanonicalAssemblyPolicy = CANONICAL_V1,
) -> CanonicalReportAssemblyResult:
    """Assemble a canonical report without invoking field reconciliation.

    This is source-quality assembly only. Target-scope selection for readiness
    remains a later orchestration concern and is intentionally not performed here.
    """

    if not isinstance(policy, CanonicalAssemblyPolicy):
        raise ReconciliationInputError(
            "policy must be a CanonicalAssemblyPolicy"
        )

    normalized_competition_id = _validate_competition_id(competition_id)
    normalized_source_ids = _normalize_snapshot_source_ids(snapshot_source_ids)

    validated_previous = (
        _revalidate_report(previous_report)
        if previous_report is not None
        else None
    )

    if (
        validated_previous is not None
        and validated_previous.competition_id != normalized_competition_id
    ):
        raise ReconciliationInputError(
            "previous_report competition_id must match current competition_id"
        )

    ordered_results = _validate_and_order_field_results(
        field_results,
        normalized_source_ids,
        policy,
    )
    unresolved = _derive_unresolved_critical_fields(ordered_results, policy)

    provisional = _build_report(
        competition_id=normalized_competition_id,
        report_version=1,
        snapshot_source_ids=normalized_source_ids,
        field_results=ordered_results,
        unresolved_critical_fields=unresolved,
    )
    provisional_fingerprint = material_fingerprint(provisional)

    if validated_previous is None:
        report_version = 1
        report_changed = True
    else:
        previous_fingerprint = material_fingerprint(validated_previous)
        report_changed = previous_fingerprint != provisional_fingerprint
        report_version = (
            validated_previous.report_version + 1
            if report_changed
            else validated_previous.report_version
        )

    report = _build_report(
        competition_id=normalized_competition_id,
        report_version=report_version,
        snapshot_source_ids=normalized_source_ids,
        field_results=ordered_results,
        unresolved_critical_fields=unresolved,
    )
    fingerprint = material_fingerprint(report)

    return CanonicalReportAssemblyResult(
        report=report,
        field_results=tuple(_copy_field_result(item) for item in ordered_results),
        report_changed=report_changed,
        assembly_policy_version=policy.policy_version,
        material_fingerprint=fingerprint,
    )
