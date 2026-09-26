"""Public API for Issue 3A Block 5 advisory recommendation assembly."""

from engine.recommendation.messages import RecommendationEvidenceError
from engine.recommendation.models import (
    RecommendationAssembly,
    RecommendationBuildInput,
    RecommendationPayload,
    RecommendationTraceContext,
    RecommendedNextWork,
    SuggestedWorkWindow,
)
from engine.recommendation.service import (
    RecommendationInputError,
    RecommendationInvariantError,
    build_recommendation,
    materialize_public_recommendation,
)

__all__ = [
    "RecommendationAssembly",
    "RecommendationBuildInput",
    "RecommendationEvidenceError",
    "RecommendationInputError",
    "RecommendationInvariantError",
    "RecommendationPayload",
    "RecommendationTraceContext",
    "RecommendedNextWork",
    "SuggestedWorkWindow",
    "build_recommendation",
    "materialize_public_recommendation",
]
