# Implementation Handoff Plan v1.0 — Draft

## Tujuan
Ubah behavioral contract yang sudah dibekukan menjadi satu executable vertical slice sebelum memperluas UI atau intelligence.

## Milestone 1 — Contracts + domain kernel
Implement Pydantic/domain schemas, enums, readiness triage, fixture loader and TRIAGE-001..008 tests. Exit: all eight fixtures pass.

## Milestone 2 — Source ingestion
Implement URL fetch abstraction, PDF intake, native extraction, OCR adapter, candidate normalization and reconciliation. Exit: critical conflicts remain visible and source evaluation can run.

## Milestone 3 — Workload + availability
Implement task graph, min/likely/max effort, local/manual commitments, availability blocks and the MVP recurrence subset.

## Milestone 4 — Solver
Implement CP-SAT candidate allocation, hard constraints, buffers and post-solver invariant checks. Exit: zero hard violations.

## Milestone 5 — Recommendation
Implement transparent candidate ranking, rationale, alternatives, trade-offs and stale-recommendation invalidation.

## Milestone 6 — Mobile vertical slice
Implement Home, My Schedule, Analyze Competition, Brief Review, Decision Support Report and Saved Plans. Exit: one competition completes the end-to-end flow.

## Milestone 7 — RevenueCat
Add entitlement after correctness-critical flow works. Entitlement must not change deadline/eligibility/conflict truth.

## Deferred
Custom ML, social/team marketplace, autonomous browser agent, direct calendar write and advanced team collaboration.
