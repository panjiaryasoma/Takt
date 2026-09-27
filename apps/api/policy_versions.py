"""Version authority for Issue 4A public decision semantics.

A version string may stay unchanged only while every material behavior listed
for that policy stays unchanged. If one listed behavior changes, the owning
version must be bumped together with its contract tests.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class PolicyAuthority:
    version: str
    material_behaviors: tuple[str, ...]
    material_parameters: tuple[tuple[str, object], ...] = ()


RECONCILIATION_POLICY = PolicyAuthority(
    version="reconciliation-v1",
    material_behaviors=(
        "multi-source candidate reconciliation",
        "source authority interpretation",
        "source scope intersection",
        "freshness and supersession interpretation",
        "canonical conflict versus usable-state semantics",
    ),
)

READINESS_PROJECTION_POLICY = PolicyAuthority(
    version="readiness-projection-v1",
    material_behaviors=(
        "canonical field-state projection into readiness",
        "canonical eligibility scope resolution",
        "submission deadline parsing and UTC normalization",
        "required technology information projection",
        "deadline extension fixed false in v1",
    ),
)

PLANNING_POLICY = PolicyAuthority(
    version="planning-policy-v1",
    material_behaviors=(
        "server-time not-before projection",
        "availability and recurrence interpretation",
        "daily project-capacity calculation",
        "workload required-closure semantics",
        "MIN LIKELY MAX FULL_SCOPE_LIKELY feasibility scenarios",
        "LIKELY public recommendation candidate pool",
        "CP-SAT hard constraints and deterministic settings",
        "candidate enumeration and maximum candidate count",
        "material-difference policy",
        "feasibility classification",
        "candidate ranking",
        "recommendation assembly and allowed actions",
        "reason and tradeoff message semantics",
    ),
    material_parameters=(
        ("public_candidate_scenario", "LIKELY"),
        ("max_candidates", 3),
        ("material_completion_delta_minutes", 30),
    ),
)


__all__ = [
    "PLANNING_POLICY",
    "READINESS_PROJECTION_POLICY",
    "RECONCILIATION_POLICY",
    "PolicyAuthority",
]
