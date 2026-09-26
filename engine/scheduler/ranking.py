"""Deterministic ordering for recommendable candidate allocations."""

from __future__ import annotations

from datetime import UTC, datetime

from packages.contracts.models import CandidateAllocation


def rank_candidate_allocations(
    candidates: tuple[CandidateAllocation, ...],
) -> tuple[CandidateAllocation, ...]:
    """Rank only recommendable candidates by fragmentation, completion, then signature."""

    valid = tuple(candidate for candidate in candidates if candidate.is_recommendable)
    ordered = sorted(
        valid,
        key=lambda candidate: (
            _candidate_rank_key(candidate),
            candidate.candidate_id,
        ),
    )

    unique: list[CandidateAllocation] = []
    seen_signatures = set()
    for candidate in ordered:
        signature = _candidate_signature(candidate)
        if signature in seen_signatures:
            continue
        seen_signatures.add(signature)
        unique.append(candidate)
    return tuple(unique)


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
    signature = _candidate_signature(candidate)
    return (len(blocks), completion, signature)


def _candidate_signature(candidate: CandidateAllocation):
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
    return tuple(
        (
            block.task_id,
            block.start.astimezone(UTC),
            block.end.astimezone(UTC),
            block.allocated_minutes,
            block.availability_source,
        )
        for block in blocks
    )
