"""Compatibility shim for the Issue 4A API service.

New code must import apps.api.services.competition_analysis. This shim exists
only while branch-local imports are migrated in the next refactor step.
"""
from apps.api.services.competition_analysis import *  # noqa: F403
