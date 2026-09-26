"""Deterministic ordering for recommendable candidate allocations."""

from __future__ import annotations

from datetime import UTC, datetime

from packages.contracts.models import CandidateAllocation


def rank_candidate_allocations(
    candidates: tuple[CandidateAllocation, ...],
) -> tuple[CandidateAllocation, ...]:
    """Rank only recommendable candidates by fragmentation, completion, then signature."""

    valid = tuple(candidate for candidate in candidates if candidate.is_recommendable)
    return tuple(sorted(valid, key=_candidate_rank_key))


def _candidate_rank_key(candidate: CandidateAllocation):
    blocks = tuple(
        sorted(
            candidate.work_blocks,
            key=lambda item: (
                item.start.astimezone(UTC),
                item.task_id,
                item.end.astimezone(UTC),
            ),
        )
    )
    completion = (
        blocks[-1].end.astimezone(UTC)
        if blocks
        else datetime.min.replace(tzinfo=UTC)
    )
    signature = tuple(
        (
            block.task_id,
            block.start.astimezone(UTC),
            block.end.astimezone(UTC),
            block.allocated_minutes,
            block.availability_source,
        )
        for block in blocks
    )
    return (len(blocks), completion, signature)
