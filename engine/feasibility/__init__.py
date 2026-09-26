"""Public API for Issue 3A Block 4 feasibility classification."""

from engine.feasibility.models import (
    FeasibilityAssessment,
    FeasibilityRun,
    FeasibilityScenario,
    FeasibilityScenarioResult,
)
from engine.feasibility.service import (
    FeasibilityExecutionError,
    FeasibilityIndeterminateError,
    FeasibilityInputError,
    FeasibilityInvariantError,
    assess_feasibility,
    assess_feasibility_run,
)

__all__ = [
    "FeasibilityAssessment",
    "FeasibilityExecutionError",
    "FeasibilityIndeterminateError",
    "FeasibilityInputError",
    "FeasibilityInvariantError",
    "FeasibilityRun",
    "FeasibilityScenario",
    "FeasibilityScenarioResult",
    "assess_feasibility",
    "assess_feasibility_run",
]
