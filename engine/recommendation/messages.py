"""Deterministic evidence-to-message registry for Block 5 recommendation."""

from __future__ import annotations

from types import MappingProxyType


class RecommendationEvidenceError(ValueError):
    """Raised when Block 4 emits an evidence code Block 5 does not understand."""


_REASON_MESSAGES = MappingProxyType(
    {
        "REQUIRED_LIKELY_INFEASIBLE": (
            "Required work does not fit at the likely effort estimate."
        ),
        "REQUIRED_MAX_INFEASIBLE": (
            "Required work no longer fits at the maximum effort estimate."
        ),
        "FULL_SCOPE_LIKELY_INFEASIBLE": (
            "The full scope does not fit at the likely effort estimate."
        ),
        "FULL_SCOPE_LIKELY_SCENARIO_UNKNOWN": (
            "Full-scope feasibility could not be determined from the current solver result."
        ),
        "ALL_REQUIRED_SCENARIOS_FEASIBLE": (
            "Required work fits across the modeled minimum, likely, and maximum effort "
            "scenarios."
        ),
        "FULL_SCOPE_LIKELY_FEASIBLE": (
            "The full scope fits at the likely effort estimate."
        ),
    }
)

_SENSITIVITY_MESSAGES = MappingProxyType(
    {
        "MINIMUM_EFFORT_SCENARIO_FEASIBLE": (
            "Required work fits at the minimum effort estimate."
        ),
        "MIN_SCENARIO_UNKNOWN": "Minimum-effort feasibility could not be determined.",
        "LIKELY_EFFORT_SCENARIO_INFEASIBLE": (
            "Required work does not fit at the likely effort estimate."
        ),
        "EFFORT_OVERRUN_BREAKS_PLAN": (
            "The current plan is sensitive to effort overruns."
        ),
        "MAX_EFFORT_SCENARIO_FEASIBLE": (
            "Required work still fits at the maximum effort estimate."
        ),
        "MAX_SCENARIO_UNKNOWN": "Maximum-effort feasibility could not be determined.",
    }
)

_TRADEOFF_MESSAGES = MappingProxyType(
    {
        "OPTIONAL_SCOPE_DOES_NOT_FIT": (
            "Some optional tasks would need to be dropped under the current constraints."
        )
    }
)


def render_rationale(
    reason_codes: tuple[str, ...],
    sensitivity_codes: tuple[str, ...],
) -> tuple[str, ...]:
    """Translate known reason/sensitivity codes in frozen deterministic order."""

    messages: list[str] = []
    for code in reason_codes:
        _append_message(messages, code, _REASON_MESSAGES, "reason")
    for code in sensitivity_codes:
        _append_message(messages, code, _SENSITIVITY_MESSAGES, "sensitivity")
    return tuple(messages)


def render_tradeoffs(tradeoff_codes: tuple[str, ...]) -> tuple[str, ...]:
    """Translate known tradeoff codes in frozen deterministic order."""

    messages: list[str] = []
    for code in tradeoff_codes:
        _append_message(messages, code, _TRADEOFF_MESSAGES, "tradeoff")
    return tuple(messages)


def _append_message(
    target: list[str],
    code: str,
    registry,
    kind: str,
) -> None:
    try:
        message = registry[code]
    except KeyError as exc:
        raise RecommendationEvidenceError(
            f"unknown {kind} evidence code: {code}"
        ) from exc
    if message not in target:
        target.append(message)
