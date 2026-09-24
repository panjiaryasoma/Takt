"""Canonical report assembly policy for reconciliation Block 4b."""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass

from packages.contracts.source import CORE_CANONICAL_FIELDS

_CANONICAL_V1_CORE_FIELDS = (
    "competition_name",
    "organizer",
    "submission_deadline",
    "registration_deadline",
    "eligibility",
    "team_size",
    "format",
    "location",
    "tracks_or_categories",
    "deliverables",
    "required_technologies",
    "judging_criteria",
    "prizes_or_benefits",
)

_CANONICAL_V1_CRITICAL_FIELDS = (
    "submission_deadline",
    "eligibility",
)

_REGISTERED_POLICIES: dict[str, tuple[tuple[str, ...], tuple[str, ...]]] = {
    "canonical-v1": (
        _CANONICAL_V1_CORE_FIELDS,
        _CANONICAL_V1_CRITICAL_FIELDS,
    ),
}


def _freeze_string_tuple(
    value: Iterable[str],
    *,
    field_name: str,
) -> tuple[str, ...]:
    if isinstance(value, (str, bytes)):
        raise ValueError(f"{field_name} must be an iterable of field names")
    try:
        frozen = tuple(value)
    except TypeError as exc:
        raise ValueError(f"{field_name} must be iterable") from exc
    if any(not isinstance(item, str) or not item for item in frozen):
        raise ValueError(f"{field_name} must contain non-empty strings")
    return frozen


@dataclass(frozen=True, slots=True)
class CanonicalAssemblyPolicy:
    """Registered immutable assembly semantics for one canonical policy version."""

    policy_version: str
    core_fields: tuple[str, ...]
    critical_fields: tuple[str, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.policy_version, str) or not self.policy_version.strip():
            raise ValueError("policy_version must be non-empty")

        core_fields = _freeze_string_tuple(
            self.core_fields,
            field_name="core_fields",
        )
        critical_fields = _freeze_string_tuple(
            self.critical_fields,
            field_name="critical_fields",
        )
        object.__setattr__(self, "core_fields", core_fields)
        object.__setattr__(self, "critical_fields", critical_fields)

        if len(core_fields) != len(set(core_fields)):
            raise ValueError("core_fields must be unique")
        if set(core_fields) != CORE_CANONICAL_FIELDS:
            raise ValueError("core_fields must match canonical contract")
        if len(critical_fields) != len(set(critical_fields)):
            raise ValueError("critical_fields must be unique")
        if not set(critical_fields).issubset(core_fields):
            raise ValueError("critical_fields must be canonical core fields")

        expected = _REGISTERED_POLICIES.get(self.policy_version)
        if expected is None:
            raise ValueError("unsupported canonical assembly policy version")

        expected_core, expected_critical = expected
        if core_fields != expected_core:
            raise ValueError(
                "core_fields must exactly match registered policy ordering"
            )
        if critical_fields != expected_critical:
            raise ValueError(
                "critical_fields must exactly match registered policy semantics"
            )


CANONICAL_V1 = CanonicalAssemblyPolicy(
    policy_version="canonical-v1",
    core_fields=_CANONICAL_V1_CORE_FIELDS,
    critical_fields=_CANONICAL_V1_CRITICAL_FIELDS,
)
