"""Deterministic comparison, scope, and supersession policy for reconciliation."""

from __future__ import annotations

import json
import math
from datetime import UTC, date, datetime
from typing import Any

from packages.contracts import SourceType

from engine.reconciliation.models import (
    CandidateObservation,
    ComparisonValue,
    ScopeDescriptor,
    ScopeRelation,
)

_SCOPE_KEYS = frozenset({"audience", "category", "region"})
_WILDCARDS = frozenset({"*", "all", "any"})
_SET_LIKE_FIELDS = frozenset(
    {
        "tracks_or_categories",
        "deliverables",
        "required_technologies",
        "judging_criteria",
        "prizes_or_benefits",
    }
)
_DEADLINE_FIELDS = frozenset({"submission_deadline", "registration_deadline"})
_OFFICIAL_UPDATE_SOURCES = frozenset(
    {
        SourceType.OFFICIAL_RULES,
        SourceType.OFFICIAL_ORGANIZER,
        SourceType.OFFICIAL_FAQ,
    }
)
_UPDATE_KINDS = frozenset({"update", "extension", "exception", "replacement"})


class UnusableNormalizedValue(ValueError):
    """Raised when a normalized value cannot be compared safely."""


def _clean_scope_value(value: Any) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        raise ValueError("scope dimensions must be strings or null")
    cleaned = value.strip().lower()
    if not cleaned:
        raise ValueError("scope dimensions must not be empty strings")
    return cleaned


def parse_scope(scope: Any) -> ScopeDescriptor:
    """Interpret the frozen audience/category/region scope shape conservatively."""

    if not isinstance(scope, dict) or not scope:
        return ScopeDescriptor(known=False)

    unsupported = {
        key for key, value in scope.items() if key not in _SCOPE_KEYS and value is not None
    }
    if unsupported:
        return ScopeDescriptor(known=False)

    try:
        descriptor = ScopeDescriptor(
            audience=_clean_scope_value(scope.get("audience")),
            category=_clean_scope_value(scope.get("category")),
            region=_clean_scope_value(scope.get("region")),
        )
    except ValueError:
        return ScopeDescriptor(known=False)

    if descriptor.key == (None, None, None):
        return ScopeDescriptor(known=False)
    return descriptor


def _is_wildcard(value: str | None) -> bool:
    return value in _WILDCARDS


def scope_relation(left: ScopeDescriptor, right: ScopeDescriptor) -> ScopeRelation:
    """Compare two scopes without treating missing metadata as broad applicability."""

    if not left.known or not right.known:
        return ScopeRelation.UNKNOWN
    if left.key == right.key:
        return ScopeRelation.SAME

    for left_value, right_value in zip(left.key, right.key, strict=True):
        if left_value is None or right_value is None:
            continue
        if _is_wildcard(left_value) or _is_wildcard(right_value):
            continue
        if left_value != right_value:
            return ScopeRelation.DISJOINT

    return ScopeRelation.OVERLAPS


def _json_key(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _canonicalize_generic(value: Any, *, set_like_lists: bool = False) -> Any:
    if value is None or isinstance(value, (bool, int, str)):
        return value
    if isinstance(value, float):
        if not math.isfinite(value):
            raise UnusableNormalizedValue("non-finite float cannot be compared")
        return value
    if isinstance(value, datetime):
        if value.tzinfo is None or value.utcoffset() is None:
            raise UnusableNormalizedValue("naive datetime cannot be compared")
        return value.astimezone(UTC).isoformat().replace("+00:00", "Z")
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, dict):
        if any(not isinstance(key, str) for key in value):
            raise UnusableNormalizedValue("structured normalized keys must be strings")
        return {
            key: _canonicalize_generic(item, set_like_lists=False)
            for key, item in sorted(value.items())
        }
    if isinstance(value, (set, frozenset)):
        items = [_canonicalize_generic(item, set_like_lists=False) for item in value]
        return sorted(items, key=_json_key)
    if isinstance(value, (list, tuple)):
        items = [_canonicalize_generic(item, set_like_lists=False) for item in value]
        if set_like_lists:
            unique = {_json_key(item): item for item in items}
            return [unique[key] for key in sorted(unique)]
        return items
    raise UnusableNormalizedValue(
        f"unsupported normalized value type: {type(value).__name__}"
    )


def _deadline_comparison(value: Any) -> ComparisonValue:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, date):
        canonical = value.isoformat()
        return ComparisonValue(key=f"date:{canonical}", canonical=canonical)
    elif isinstance(value, str):
        cleaned = value.strip()
        if not cleaned:
            raise UnusableNormalizedValue("deadline normalized value is empty")
        try:
            if "T" not in cleaned:
                parsed_date = date.fromisoformat(cleaned)
                canonical = parsed_date.isoformat()
                return ComparisonValue(key=f"date:{canonical}", canonical=canonical)
            parsed = datetime.fromisoformat(cleaned.replace("Z", "+00:00"))
        except ValueError as exc:
            raise UnusableNormalizedValue(
                "deadline normalized value is not ISO date/datetime"
            ) from exc
    else:
        raise UnusableNormalizedValue("deadline normalized value has unsupported type")

    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise UnusableNormalizedValue("deadline datetime must include timezone")
    canonical = parsed.astimezone(UTC).isoformat().replace("+00:00", "Z")
    return ComparisonValue(key=f"instant:{canonical}", canonical=canonical)


def comparison_value(field_name: str, normalized_value: Any) -> ComparisonValue:
    """Build a stable field-aware semantic equality key."""

    if normalized_value is None:
        raise UnusableNormalizedValue("normalized value is null")
    if field_name in _DEADLINE_FIELDS:
        return _deadline_comparison(normalized_value)

    canonical = _canonicalize_generic(
        normalized_value,
        set_like_lists=field_name in _SET_LIKE_FIELDS,
    )
    return ComparisonValue(key=_json_key(canonical), canonical=canonical)


def _parse_effective_at(metadata: Any) -> datetime | None:
    if not isinstance(metadata, dict):
        return None
    value = metadata.get("effective_at")
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
        except ValueError:
            return None
    else:
        return None
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        return None
    return parsed.astimezone(UTC)


def _authority_is_interpretable(observation: CandidateObservation) -> bool:
    metadata = observation.source_record.authority_rank
    if not isinstance(metadata, dict):
        return False
    basis = metadata.get("basis", metadata.get("kind"))
    return isinstance(basis, str) and bool(basis.strip())


def _explicit_supersedes(metadata: dict[str, Any], source_id: str) -> bool:
    values = metadata.get("supersedes_source_ids", ())
    if not isinstance(values, (list, tuple, set, frozenset)):
        return False
    return source_id in {value for value in values if isinstance(value, str)}


def _field_update_applies(metadata: dict[str, Any], field_name: str) -> bool:
    update_kind = metadata.get("update_kind")
    if not isinstance(update_kind, str) or update_kind.strip().lower() not in _UPDATE_KINDS:
        return False
    fields = metadata.get("applies_to_fields", ())
    if not isinstance(fields, (list, tuple, set, frozenset)):
        return False
    return field_name in {value for value in fields if isinstance(value, str)}


def source_supersedes(
    newer: CandidateObservation,
    older: CandidateObservation,
    *,
    field_name: str,
) -> bool:
    """Whether newer deterministically supersedes older for this field.

    retrieved_at is intentionally ignored. Freshness comes only from an
    explicit aware effective_at plus update/replacement evidence.
    """

    if newer.source_id == older.source_id:
        return False
    if newer.source_record.source_type not in _OFFICIAL_UPDATE_SOURCES:
        return False
    if not _authority_is_interpretable(newer):
        return False

    relation = scope_relation(parse_scope(newer.field.scope), parse_scope(older.field.scope))
    if relation not in {ScopeRelation.SAME, ScopeRelation.OVERLAPS}:
        return False

    newer_metadata = newer.source_record.freshness_metadata
    older_metadata = older.source_record.freshness_metadata
    if not isinstance(newer_metadata, dict):
        return False

    newer_effective = _parse_effective_at(newer_metadata)
    if newer_effective is None:
        return False
    if _explicit_supersedes(newer_metadata, older.source_id):
        return True

    older_effective = _parse_effective_at(older_metadata)
    if older_effective is None or newer_effective <= older_effective:
        return False
    return _field_update_applies(newer_metadata, field_name)
