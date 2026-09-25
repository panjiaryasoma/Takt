"""Public Block 3 candidate-allocation API."""

from engine.scheduler.models import SolverConfig, SolverResult, SolverRunStatus
from engine.scheduler.service import SolverInputError, solve_candidate_allocations

__all__ = [
    "SolverConfig",
    "SolverInputError",
    "SolverResult",
    "SolverRunStatus",
    "solve_candidate_allocations",
]
