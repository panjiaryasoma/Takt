# Testing dan Evaluation Plan v1.0 — Draft

## Layer 1 — Schema
YAML/JSON/Pydantic validation, enum values, required fields and invalid-state rejection.

## Layer 2 — Domain rules
TRIAGE-001..008 plus timezone, recurrence, missing-vs-false and source-authority tests.

## Layer 3 — Source extraction
Use SOURCE_EVALUATION_SUITE_001-030, real snapshots and controlled mixed-PDF derivatives. Track critical-field accuracy, provenance coverage and conflict recall.

## Layer 4 — Solver
Invariant tests: no fixed overlap, dependencies respected, daily capacity respected, deadline respected, zero hard violations for recommendable candidates.

## Layer 5 — Integration
INTEGRATION-001 first, then source→canonical→triage; canonical+schedule→tasks→solver; candidate→recommendation→human accept; material change→stale invalidation→re-evaluation.

## Layer 6 — Mobile/UI
Form validation, progress states, conflict review, suggestion-vs-commitment distinction, accessibility and cached-plan behavior.

## Layer 7 — Monetization
Entitlement cannot change canonical facts, triage, blocker warnings or source conflicts.

## Layer 8 — Human evaluation
Measure brief comprehension, rationale comprehension, realism of suggested windows, and edit/ignore behavior. Acceptance rate alone is not recommendation quality.

Critical contract test harus hijau sebelum demo polish menghabiskan sisa implementation budget.
