# Baseline Contract

**Version:** 1.0  
**Status:** ACTIVE PREPRODUCTION BASELINE

## Product contract
The product is a calendar-aware competition decision-support system. It understands competition sources, preserves provenance, surfaces ambiguity, evaluates readiness deterministically, decomposes work, models real available capacity, generates feasible candidate allocations, explains recommendations/trade-offs, and leaves consequential decisions to the user.

## Authority boundaries

### AI / LLM may
- extract structured facts from prose;
- normalize source content;
- propose task decomposition;
- draft explanations.

### Deterministic systems must
- validate schemas;
- compare date/time/timezones;
- run readiness triage;
- enforce calendar collisions and dependencies;
- verify CP-SAT results;
- invalidate stale recommendations.

### Human retains authority to
- correct source interpretation;
- decide whether to participate;
- accept/edit scope;
- accept/ignore recommendations;
- create calendar commitments;
- perform submission/payment/external actions.

## Source contract
```text
SourceRecord[]
→ CandidateExtractionReport(s)
→ Field-Level Reconciliation
→ CanonicalCompetitionReport
```

Critical fields retain provenance. Unresolved critical conflicts remain visible.

## Readiness states
- `READY_TO_EVALUATE`
- `NEEDS_REVIEW`
- `ELIGIBILITY_BLOCKED`
- `DEADLINE_PASSED`
- `INSUFFICIENT_INFORMATION`

Readiness is a factual gate and must never output JOIN/DO_NOT_JOIN or equivalent personal directives.

## Feasibility states
- `FEASIBLE`
- `FEASIBLE_WITH_TRADEOFFS`
- `TIGHT_CAPACITY`
- `NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS`

They describe the modeled plan under current constraints, not the user's ability.

## Solver contract
CP-SAT returns `CandidateAllocation[]`. Recommendable candidates have zero hard-constraint violations. Solver output is not automatically committed to the calendar.

## Recommendation contract
Every recommendation references a valid candidate, exposes rationale/assumptions/trade-offs, and surfaces alternatives where materially different feasible options exist.

## Data contract
Synthetic data is valid for engineering and fixtures, not real-world product-performance claims.

## Monetization contract
RevenueCat may gate capacity/features but may never alter deadline truth, eligibility truth, source conflicts, readiness blockers, or solver correctness.

## Change control
Any semantic change to canonical fields, enums, authority boundaries, triage, hard constraints, recommendation semantics, or feature availability requires a versioned change request.
