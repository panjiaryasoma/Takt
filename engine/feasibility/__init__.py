"""Public API for Issue 3A Block 4 feasibility classification."""

from engine.feasibility.models import (
    FeasibilityAssessment,
    FeasibilityScenario,
    FeasibilityScenarioResult,
)
from engine.feasibility.service import (
    FeasibilityExecutionError,
    FeasibilityIndeterminateError,
    FeasibilityInputError,
    FeasibilityInvariantError,
    assess_feasibility,
)

__all__ = [
    "FeasibilityAssessment",
    "FeasibilityExecutionError",
    "FeasibilityIndeterminateError",
    "FeasibilityInputError",
    "FeasibilityInvariantError",
    "FeasibilityScenario",
    "FeasibilityScenarioResult",
    "assess_feasibility",
]
