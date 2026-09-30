"""Canonical semantic projection for deterministic evaluation assertions.

5A deliberately strips only execution identity. Domain identity, ordering,
timestamps under a fixed clock, fingerprints, actions, and explanation material
remain observable and therefore remain part of deterministic equality.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from pydantic import BaseModel

_EXECUTION_ONLY_KEYS = frozenset({"evaluation_id"})


def semantic_projection(value: BaseModel | Mapping[str, Any]) -> dict[str, Any]:
    """Return a JSON-compatible projection without execution-only identity.

    evaluation_id is removed recursively, including candidate and
    recommendation references. Candidate IDs, task IDs, report versions,
    evaluated_at, fingerprints, sequence ordering, and all domain state remain.
    """

    raw: Any
    if isinstance(value, BaseModel):
        raw = value.model_dump(mode="json", warnings=False)
    else:
        raw = dict(value)

    projected = _project(raw)
    if not isinstance(projected, dict):
        raise TypeError("semantic projection root must be an object")
    return projected


def _project(value: Any) -> Any:
    if isinstance(value, Mapping):
        return {
            str(key): _project(item)
            for key, item in value.items()
            if key not in _EXECUTION_ONLY_KEYS
        }
    if isinstance(value, list):
        return [_project(item) for item in value]
    if isinstance(value, tuple):
        return [_project(item) for item in value]
    return value
