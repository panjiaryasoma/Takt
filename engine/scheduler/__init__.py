"""Public Block 3 candidate-allocation API."""

from engine.scheduler.models import SolverConfig, SolverResult, SolverRunStatus
from engine.scheduler.ranking import rank_candidate_allocations
from engine.scheduler.service import SolverInputError, solve_candidate_allocations

__all__ = [
    "SolverConfig",
    "SolverInputError",
    "SolverResult",
    "SolverRunStatus",
    "rank_candidate_allocations",
    "solve_candidate_allocations",
]
