# PRD Schema Alignment Addendum

**Version:** 1.0  
**Date:** 2026-09-21

This file aligns `simple_prd.md` with the machine-readable schemas and evaluation assets. It exists because prose PRDs have a charming habit of being "clear" until two engineers implement different interpretations.

## 1. Source-of-truth hierarchy
1. `domain_rules_v1.0.yaml` — behavioral invariants.
2. `SOURCE_SCHEMA.md` — source, evidence, candidate-report and canonical-report contracts.
3. `feature_schema_v1.0.yaml` — feature inventory and release boundaries.
4. `simple_prd.md` — product intent and user-facing requirements.
5. `evaluation_spec_v1.0.yaml` — acceptance methodology.
6. `evaluation_matrix_v1.0.csv` — executable pre-production case inventory.

When prose conflicts with a critical domain invariant, the domain rule wins until an explicit versioned change is made.

## 2. PRD → feature alignment

| PRD area | Canonical feature IDs |
|---|---|
| Personal calendar | F-001, F-002 |
| URL/PDF intake | F-003, F-004 |
| Dual-path document extraction | F-005, F-006, F-007 |
| Reconciliation/canonical report | F-008, F-009 |
| Competition readiness | F-010 |
| Task/workload modeling | F-011, F-012 |
| Constraint model + CP-SAT | F-013, F-014 |
| Recommendation/decision support | F-015, F-016, F-017 |
| Accepted commitment/progress | F-018, F-019, F-020, F-021 |
| Monetization | F-022 |
| Export/calendar integration | F-023, F-024 |
| Future learned effort adjustment | F-025 |

## 3. Core data contracts

### Source ingestion output
`SourceRecord[] + EvidenceSpan[]`

### Extraction output
`CandidateExtractionReport` — FW1 and FW2 are peers; neither is canonical.

### Reconciliation output
`CanonicalCompetitionReport`

### Readiness output
```yaml
status: READY_TO_EVALUATE | NEEDS_REVIEW | ELIGIBILITY_BLOCKED | DEADLINE_PASSED | INSUFFICIENT_INFORMATION
blocking_reasons: []
review_items: []
passed_checks: []
```

### Workload output
```yaml
tasks:
  - id
  - name
  - dependencies
  - min_hours
  - likely_hours
  - max_hours
  - mandatory
  - evidence_or_basis
```

### Candidate allocation output
```yaml
candidate_id: string
feasible: boolean
work_blocks: []
buffer_hours: number
hard_constraint_violations: []
assumptions: []
```

### Recommendation output
```yaml
recommended_candidate_id: string | null
recommended_next_work: []
suggested_windows: []
alternatives: []
rationale: []
tradeoffs: []
assumptions: []
```

A null recommendation is allowed when evidence or feasibility is insufficient.

## 4. State separation
These states must not be collapsed:
- source extraction confidence;
- canonical field verification state;
- readiness triage;
- solver feasibility;
- recommendation ranking;
- human acceptance.

High-confidence OCR does not equal `VERIFIED`; `READY_TO_EVALUATE` does not equal `FEASIBLE`; `FEASIBLE` does not equal "user should join."

## 5. Decision-support language
Approved: "Feasible under current assumptions", "Tight capacity", "Recommended work window", "Alternative", and explicit buffer/trade-off language.

Disallowed as system conclusions: "You should definitely join", "You cannot do this" when only current constraints are infeasible, "This is the best competition for you", or "You must work at 19:00".

## 6. PDF late-fusion alignment
`FR-005` requires independent candidate reports. The reconciliation boundary exists after both reports, not inside OCR routing.

Efficiency optimization is allowed at page/region level, but must not change the logical contract: each path reports what it observed; skipped paths record why; critical mixed-content fixtures run both paths in evaluation.

## 7. Calendar alignment
The domain model distinguishes FIXED commitment, FLEXIBLE commitment, FREE block, accepted competition commitment, and suggested work window.

Only accepted commitments affect the user's committed plan as competition work.

## 8. Evaluation alignment
Every MVP requirement FR-001..FR-022 appears in `feature_traceability_v1.0.csv`.

Critical invariants:
- zero false READY on known expired/ineligible fixtures;
- zero CP-SAT hard-constraint violations;
- 100% provenance coverage for critical canonical fields;
- 100% recommendation-to-candidate traceability;
- zero silent calendar/external actions.

## 9. Deferred decisions
The schemas intentionally do not lock LLM vendor/model, OCR engine, mobile framework, backend cloud vendor, or paid-tier limits. Those are implementation decisions unless they change product behavior or evaluation contracts.

## 10. Data-strategy alignment
The PRD does not authorize a custom learned model merely because a synthetic dataset can be generated.

Data/model decisions are governed by `4_DATA_STRATEGY/`. Synthetic data is valid for engineering and deterministic/adversarial evaluation, but synthetic-only predictive performance is not product evidence. The MVP remains valid without a custom-trained ML model.
