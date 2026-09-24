"""Deterministic scope, equality, authority, and freshness policy."""

from __future__ import annotations

import json
import math
from datetime import UTC, date, datetime
from typing import Any

from packages.contracts import SourceRecord, SourceType

from engine.reconciliation.models import (
    AuthorityDescriptor,
    CandidateObservation,
    ComparisonValue,
    FreshnessDescriptor,
    ReconciliationInputError,
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
_UPDATE_KINDS = frozenset({"update", "extension", "exception", "replacement"})
_RULES_UPDATE_KINDS = frozenset({"update", "replacement"})
_ORGANIZER_UPDATE_KINDS = _UPDATE_KINDS


class UnusableNormalizedValue(ValueError):
    """Raised when a normalized value cannot be compared safely."""


def _clean_scope_value(value: Any) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        raise ReconciliationInputError("scope dimensions must be strings or null")
    cleaned = value.strip().lower()
    if not cleaned:
        raise ReconciliationInputError("scope dimensions must not be empty strings")
    return cleaned


def parse_scope(scope: Any) -> ScopeDescriptor:
    """Parse the frozen audience/category/region scope shape.

    Empty/null-only mappings are valid but unknown. Malformed shapes fail loudly.
    `all`/`any`/`*` are broad applicability; `general` is intentionally literal.
    """

    if not isinstance(scope, dict):
        raise ReconciliationInputError("scope metadata must be an object")

    unsupported = {
        key for key, value in scope.items() if key not in _SCOPE_KEYS and value is not None
    }
    if unsupported:
        names = ", ".join(sorted(unsupported))
        raise ReconciliationInputError(f"unsupported scope dimensions: {names}")

    descriptor = ScopeDescriptor(
        audience=_clean_scope_value(scope.get("audience")),
        category=_clean_scope_value(scope.get("category")),
        region=_clean_scope_value(scope.get("region")),
    )
    if descriptor.key == (None, None, None):
        return ScopeDescriptor(known=False)
    return descriptor


def _is_wildcard(value: str | None) -> bool:
    return value in _WILDCARDS


def scope_relation(left: ScopeDescriptor, right: ScopeDescriptor) -> ScopeRelation:
    """Compare two scopes without treating unknown metadata as broad scope."""

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


def _intersect_dimension(left: str | None, right: str | None) -> tuple[bool, str | None]:
    if left is None:
        return True, right
    if right is None:
        return True, left
    if _is_wildcard(left):
        return True, right
    if _is_wildcard(right):
        return True, left
    if left == right:
        return True, left
    return False, None


def intersect_scopes(
    source_scope: ScopeDescriptor,
    candidate_scope: ScopeDescriptor,
) -> ScopeDescriptor | None:
    """Return effective applicability without allowing candidate scope expansion.

    None means both scopes are valid/known but have an empty intersection.
    Unknown metadata stays unknown instead of being guessed broad.
    """

    if not source_scope.known or not candidate_scope.known:
        return ScopeDescriptor(known=False)

    values: list[str | None] = []
    for source_value, candidate_value in zip(
        source_scope.key,
        candidate_scope.key,
        strict=True,
    ):
        compatible, value = _intersect_dimension(source_value, candidate_value)
        if not compatible:
            return None
        values.append(value)

    return ScopeDescriptor(
        audience=values[0],
        category=values[1],
        region=values[2],
    )


def _parse_nonempty_string_list(value: Any, *, field_name: str) -> tuple[str, ...]:
    if value is None:
        return ()
    if not isinstance(value, (list, tuple, set, frozenset)):
        raise ReconciliationInputError(f"{field_name} must be a list of strings")
    parsed: list[str] = []
    for item in value:
        if not isinstance(item, str) or not item.strip():
            raise ReconciliationInputError(f"{field_name} must contain non-empty strings")
        parsed.append(item.strip())
    return tuple(sorted(set(parsed)))


def parse_authority(source: SourceRecord) -> AuthorityDescriptor:
    """Validate the internal authority contract without numeric winner logic."""

    metadata = source.authority_rank
    if not isinstance(metadata, dict):
        raise ReconciliationInputError(authority_rank must be an object)")

    basis = metadata.get("basis", metadata.get("kind"))
    if basis is None:
        normalized_basis = None
    elif not isinstance(basis, str) or not basis.strip():
        raise ReconciliationInputError("authority basis must be a non-empty string")
    else:
        normalized_basis = basis.strip().lower()
        allowed = {item.value for item in SourceType}
        if normalized_basis not in allowed:
            raise ReconciliationInputError(
                f"unknown authority basis: {normalized_basis!r}"
            )
        if normalized_basis != source.source_type.value:
            raise ReconciliationInputError(
                "authority basis must match SourceRecord.source_type"
            )

    tier = metadata.get("tier")
    if tier is not None:
        if isinstance(tier, bool) or not isinstance(tier, int) or tier < 0:
            raise ReconciliationInputError("authority tier must be a non-negative integer")

    return AuthorityDescriptor(
        source_type=source.source_type,
        basis=normalized_basis,
        tier=tier,
    )


def _parse_effective_at(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
        except ValueError as exc:
            raise ReconciliationInputError("freshness effective_at must be ISO datetime") from exc
    else:
        raise ReconciliationInputError("freshness effective_at must be ISO datetime")

    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ReconciliationInputError("freshness effective_at must include timezone")
    return parsed.astimezone(UTC)


def parse_freshness(source: SourceRecord) -> FreshnessDescriptor:
    """Validate the internal freshness/update contract.

    Missing effective_at is valid-but-unknown. Malformed values are input errors.
    retrieved_at is intentionally absent from this policy.
    """

    metadata = source.freshness_metadata
    if not isinstance(metadata, dict):
        raise ReconciliationInputError("freshness_metadata must be an object")

    effective_at = _parse_effective_at(metadata.get("effective_at"))
    supersedes_source_ids = _parse_nonempty_string_list(
        metadata.get("supersedes_source_ids"),
        field_name="supersedes_source_ids",
    )
    applies_to_fields = _parse_nonempty_string_list(
        metadata.get("applies_to_fields"),
        field_name="applies_to_fields",
    )

    update_kind = metadata.get("update_kind")
    if update_kind is not None:
        if not isinstance(update_kind, str) or not update_kind.strip():
            raise ReconciliationInputError("update_kind must be a non-empty string")
        update_kind = update_kind.strip().lower()
        if update_kind not in _UPDATE_KINDS:
            raise ReconciliationInputError(f"unsupported update_kind: {update_kind!r}")

    return FreshnessDescriptor(
        effective_at=effective_at,
        supersedes_source_ids=supersedes_source_ids,
        update_kind=update_kind,
        applies_to_fields=applies_to_fields,
    )


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


def _authority_allows_supersession(
    newer: CandidateObservation,
    older: CandidateObservation,
) -> bool:
    """Apply conservative contextual authority, never a universal numeric ranking."""

    if not newer.authority.known or not older.authority.known:
        return False

    newer_type = newer.authority.source_type
    older_type = older.authority.source_type
    update_kind = newer.freshness.update_kind

    if newer_type is SourceType.SECONDARY:
        return False
    if newer_type is SourceType.PLATFORM:
        return False
    if newer_type is SourceType.DERIVED_FIXTURE:
        return False
    if newer_type is SourceType.OFFICIAL_FAQ:
        return False

    if newer_type is SourceType.OFFICIAL_ORGANIZER:
        return update_kind in _ORGANIZER_UPDATE_KINDS

    if newer_type is SourceType.OFFICIAL_RULES:
        if update_kind not in _RULES_UPDATE_KINDS:
            return False
        return older_type in {
            SourceType.OFFICIAL_RULES,
            SourceType.OFFICIAL_ORGANIZER,
            SourceType.OFFICIAL_FAQ,
            SourceType.PLATFORM,
            SourceType.SECONDARY,
            SourceType.DERIVED_FIXTURE,
        }

    return False


def _has_update_evidence(
    newer: CandidateObservation,
    older: CandidateObservation,
    *,
    field_name: str,
) -> bool:
    freshness = newer.freshness
    explicit_pointer = older.source_id in freshness.supersedes_source_ids
    field_scoped = field_name in freshness.applies_to_fields
    return explicit_pointer or field_scoped


def source_supersedes(
    newer: CandidateObservation,
    older: CandidateObservation,
    *,
    field_name: str,
) -> bool:
    """Whether newer deterministically supersedes older for this field.

    Required order is scope applicability -> authority policy -> effective-time
    ordering -> update/replacement evidence. retrieved_at and confidence never decide.
    """

    if newer.source_id == older.source_id:
        return False

    relation = scope_relation(newer.effective_scope, older.effective_scope)
    # V1 only auto-resolves exact same applicability. Partial-overlap replacement
    # needs explicit scoped-precedence semantics before it can be canonicalized safely.
    if relation is not ScopeRelation.SAME:
        return False
    if not _authority_allows_supersession(newer, older):
        return False

    newer_effective = newer.freshness.effective_at
    older_effective = older.freshness.effective_at
    if newer_effective is None or older_effective is None:
        return False
    if newer_effective <= older_effective:
        return False

    return _has_update_evidence(newer, older, field_name=field_name)
