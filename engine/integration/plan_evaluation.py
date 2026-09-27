"""Compatibility shim for the Issue 4A API service.

New code must import apps.api.services.plan_evaluation. This shim exists only
while branch-local imports are migrated in the next refactor step.
"""
from apps.api.services.plan_evaluation import *  # noqa: F403
