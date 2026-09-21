# Simple PRD — Competition Decision Support System

**Version:** 1.0  
**Date:** 2026-09-21  
**Status:** Pre-production baseline  
**Brand name:** not locked

## 1. Product summary

A mobile-first decision-support application for people considering or working on time-bounded competitions.

The application reads competition URLs/PDFs, constructs a canonical competition report with source provenance, checks readiness/eligibility, estimates work, compares it with the user's real calendar, generates feasible candidate work allocations, and presents recommendations, alternatives, risks, assumptions, and trade-offs.

It does not silently schedule the user's life.

## 2. Goals
1. Reduce manual reconstruction of competition rules.
2. Surface eligibility/deadline blockers before planning.
3. Make source conflicts visible instead of hiding them.
4. Convert requirements into inspectable tasks and workload ranges.
5. Use calendar constraints to test feasibility.
6. Recommend next work windows without converting suggestions into commitments automatically.
7. Preserve human authority at every consequential boundary.
8. Be useful without custom-trained ML.

## 3. Non-goals
- social network;
- teammate marketplace;
- autonomous registration or submission;
- automatic payments;
- automatic calendar modification;
- guaranteed completion prediction;
- generic life planner;
- generic Jira/Notion replacement;
- custom ML trained on synthetic labels merely to claim "AI".

## 4. Primary personas

### P1 — Student builder
Has classes, assignments and irregular free time. Finds hackathons from social media or Devpost and struggles to determine whether another competition is realistic.

### P2 — Working builder
Has fixed work blocks and narrower evening/weekend capacity. Needs trade-offs and buffer visibility.

### P3 — Small team lead
Needs to consider multiple members' manually entered availability, but does not need social discovery or chat.

## 5. Core user journey

### Journey A — Understand an opportunity
1. User pastes URL or uploads PDF.
2. Backend ingests web/PDF content.
3. Native text and visual/OCR pipelines independently produce candidate reports.
4. Reconciliation creates a canonical competition report.
5. Critical conflicts/missing fields are shown for review.
6. Competition readiness triage returns a factual status.

### Journey B — Evaluate feasibility
1. System decomposes confirmed requirements into tasks/milestones.
2. Workload is represented as min/likely/max.
3. Local calendar is transformed into busy/free blocks.
4. CP-SAT generates candidate allocations that obey hard constraints.
5. Recommendation layer ranks/explains options.
6. User sees feasibility state, suggested next work, alternatives, risks, assumptions and trade-offs.

### Journey C — Accept and execute
1. User accepts a suggestion or chooses an alternative.
2. Accepted commitment can be saved to the local plan.
3. User updates progress.
4. Material changes trigger re-evaluation, not silent mutation.

## 6. Information architecture

```text
HOME
├── My Schedule
│   ├── Calendar
│   └── Add Commitment
│
├── Analyze Competition
│   ├── Paste URL / Upload PDF
│   ├── Analysis Progress
│   ├── Competition Brief Review
│   └── Decision Support Report
│
└── Saved Plans
    ├── Competition Detail
    ├── Suggested Plan / Projection
    └── Progress / Re-evaluate
```

## 7. Functional requirements

### FR-001 Personal commitments
User can create fixed and flexible commitments with date/time, recurrence, and category.

### FR-002 Availability model
System converts commitments into available work blocks while preserving timezone and recurrence semantics.

### FR-003 Competition URL ingestion
System accepts HTTP(S) competition URLs and records retrieval metadata.

### FR-004 PDF ingestion
System accepts PDF sources and records document/page provenance.

### FR-005 Dual-path extraction
For PDFs, FW1 native extraction and FW2 visual/OCR extraction can run independently and produce the same candidate-report schema.

### FR-006 Field-level reconciliation
System reconciles candidate fields using normalized values, source authority, context and evidence. Confidence alone cannot silently resolve critical conflicts.

### FR-007 Canonical Competition Report
System stores a canonical report containing deadline, registration deadline, eligibility, team size, format/location, tracks, deliverables, judging criteria, required technology, prizes/benefits, and provenance.

### FR-008 Human source review
Critical fields in conflict, missing, or below evidence threshold require review before the system may claim readiness.

### FR-009 Competition readiness triage
Deterministic triage statuses:
- `READY_TO_EVALUATE`
- `NEEDS_REVIEW`
- `ELIGIBILITY_BLOCKED`
- `DEADLINE_PASSED`
- `INSUFFICIENT_INFORMATION`

### FR-010 Task decomposition
System converts competition requirements into candidate tasks, milestones, dependencies, skills, and submission work.

### FR-011 Workload estimation
Every task estimate is a range (`min`, `likely`, `max`) with a stated basis. Point estimates may be displayed only as a derived convenience.

### FR-012 Calendar-aware feasibility
System evaluates workload against real available blocks, not only total free hours.

### FR-013 CP-SAT candidate allocations
Solver produces one or more feasible candidate allocations under hard constraints. Solver output is not automatically committed to the user's calendar.

### FR-014 Recommendation layer
System ranks candidate allocations and explains recommended next work, suggested work windows, alternatives, buffer impact, dependency impact, and relevant assumptions.

### FR-015 Feasibility states
- `FEASIBLE`
- `FEASIBLE_WITH_TRADEOFFS`
- `TIGHT_CAPACITY`
- `NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS`

These describe the modeled plan, not the user's ability or personal fitness.

### FR-016 Human decision
User can accept, choose an alternative, edit constraints, or ignore a recommendation.

### FR-017 Accepted commitment
Only an explicitly accepted suggestion becomes part of the user's local plan.

### FR-018 Progress
User can mark work complete and optionally record actual effort.

### FR-019 Re-evaluation
Material changes to calendar, scope, deadline, task duration, or team capacity invalidate affected recommendations and trigger a new evaluation.

### FR-020 Saved plans
User can view saved competitions, latest decision-support state, progress, risks, and next recommendation.

### FR-021 Entitlement
RevenueCat gates premium capacity/features but must never change the correctness of critical facts, eligibility checks, deadline handling, or conflict warnings.

### FR-022 Export
User can export an explainable plan summary. Calendar write/export must require explicit action.

## 8. Canonical outputs
- `CompetitionBrief`: source-grounded facts only.
- `ReadinessTriage`: deterministic factual gate.
- `WorkloadModel`: tasks + dependencies + effort ranges.
- `CandidateAllocation[]`: feasible solver outputs.
- `Recommendation`: human-readable ranking/explanation over candidates.
- `DecisionSupportReport`: brief + readiness + capacity + workload + feasibility + recommendation + alternatives + risks + assumptions + trade-offs.

## 9. Data and privacy

### Local-first
Prefer local storage for event titles/details, routine labels, accepted commitments, progress, and saved plan cache.

### Cloud-minimized planning payload
Where possible, backend receives busy/free intervals, timezone, daily capacity/preferences, and task model rather than sensitive event names.

No claim is made that the product is "private" merely because storage is local-first; telemetry, backend requests, crash reporting and third-party providers must be documented before launch.

## 10. AI use
AI/LLM is appropriate for structured extraction from prose, contextual normalization, requirement/task decomposition, and explanation drafting.

AI is not authoritative for current time, arithmetic, deadline comparison, timezone conversion, hard eligibility checks once predicates are known, calendar collision, or CP-SAT constraint satisfaction.

## 11. Deterministic engines
- schema validation;
- source-state machine;
- readiness triage;
- date/time normalization;
- recurrence expansion;
- availability calculation;
- CP-SAT candidate generation;
- hard-constraint validation;
- post-solver invariant checks.

## 12. Mixed PDF strategy

```text
PDF
├── FW1 native/structured extraction → CandidateReport A
└── FW2 visual/OCR extraction       → CandidateReport B

A + B
  ↓
field-level reconciliation
  ↓
Canonical Competition Report
```

Rules:
- do not call both candidate reports canonical;
- preserve page/source evidence;
- preserve conflicts;
- OCR-only evidence can fill native-text gaps;
- agreement across independent paths may increase verification status;
- disagreement on critical fields cannot be resolved by confidence score alone.

## 13. Recommendation policy
A recommendation is valid only if:
1. it maps to a solver candidate;
2. candidate passes all hard constraints;
3. rationale names at least one scheduling factor;
4. relevant assumptions are visible;
5. alternatives are shown when materially different feasible candidates exist.

## 14. MVP screens
1. Home
2. My Schedule
3. Add Commitment
4. Analyze Competition
5. Analysis Progress
6. Competition Brief Review
7. Decision Support Report
8. Suggested Plan / Projection
9. Saved Plans
10. Competition Detail / Progress
11. Re-evaluation

## 15. Monetization hypothesis

Potential Free: limited active competitions, basic source analysis, one current recommendation set, local schedule.

Potential Pro: more active competitions, advanced what-if analysis, more alternatives, extended history, team-capacity modeling, export/history tools.

This is a **hypothesis**, not validated willingness-to-pay evidence.

## 16. Non-functional requirements

### Reliability
- No hard-constraint violation may appear as a valid recommendation.
- Critical canonical fields must carry provenance.

### Explainability
- Recommendation rationale and assumptions visible.
- Conflict/missing-state visible.

### Performance targets for MVP
- cached app screens feel local;
- URL analysis target p50 <= 15 s for ordinary pages;
- PDF analysis target reported progressively; no fixed SLA until benchmarked;
- re-evaluation without new source ingestion target p50 <= 5 s for normal task counts.

Targets are engineering goals, not externally promised SLAs.

### Accessibility
- all primary actions tap/click accessible;
- no color-only status encoding;
- readable confidence/conflict states;
- time and date text always shown, not icon-only.

### Auditability
Persist source retrieval timestamp, extraction pipeline/version, canonical field provenance, rule version, solver configuration/version, and recommendation basis.

## 17. Metrics

Pre-launch evaluation metrics are defined in `evaluation_spec_v1.0.yaml`.

Product metrics after instrumentation:
- analyze → brief-confirm conversion;
- brief-confirm → decision-report conversion;
- recommendation acceptance rate;
- alternative selection rate;
- re-evaluation rate;
- source-review rate;
- extraction conflict frequency;
- user edit rate for extracted fields;
- estimate-vs-actual error where users record actual effort.

Do not use recommendation acceptance alone as a proxy for recommendation quality.

## 18. Launch gates

MVP cannot be called ready unless:
- source suite passes critical extraction thresholds;
- zero false-ready cases for known hard blockers;
- zero solver hard-constraint violations in evaluation;
- every critical field is provenance-backed;
- recommendation traceability is complete;
- local/cloud privacy boundary is documented;
- RevenueCat entitlement cannot suppress critical warnings.

## 19. Open decisions
- final product name;
- mobile framework;
- exact backend hosting;
- LLM provider/model;
- whether FW2 uses Tesseract, RapidOCR, a vision model, or an ensemble in MVP;
- whether direct calendar integration is Shipaton MVP or post-MVP;
- exact RevenueCat free/pro boundary;
- team-capacity depth for V1.
