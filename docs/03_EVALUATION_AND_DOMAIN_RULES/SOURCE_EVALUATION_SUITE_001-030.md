# SOURCE_EVALUATION_SUITE_001-030

**Version:** 1.0  
**Purpose:** Pre-production cases grounded in real public source families and technical standards.

## SE-001 — Shipaton deadline/timezone

- **Category:** source
- **Expected behavior:** Critical deadline retains original timezone and provenance.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-002 — Shipaton student path

- **Category:** source
- **Expected behavior:** Conditional student eligibility is represented without flattening.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-003 — Shipaton submission artifacts

- **Category:** source
- **Expected behavior:** Submission artifacts are separated from product features.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-004 — Shipaton categories

- **Category:** source
- **Expected behavior:** General event scope is separated from category-specific criteria.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-005 — Swift regional age rules

- **Category:** source
- **Expected behavior:** Jurisdiction-dependent age predicates are preserved.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-006 — Swift legal deadline

- **Category:** source
- **Expected behavior:** Legal terms outrank matching summary copy for exact deadline.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-007 — Swift submission window

- **Category:** source
- **Expected behavior:** Open window and final deadline are distinct.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-008 — Imagine Cup composite rules

- **Category:** source
- **Expected behavior:** Eligibility, team size, technology and artifacts map to distinct fields.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-009 — HackMIT exception

- **Category:** source
- **Expected behavior:** Applicable exception is preserved rather than simplified away.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-010 — Game Off deadline/repository

- **Category:** source
- **Expected behavior:** Deadline and repository requirement remain distinct.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-011 — Game Off event page

- **Category:** source
- **Expected behavior:** Related source corroborates without losing self-provenance.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-012 — Game Off team size

- **Category:** source
- **Expected behavior:** Team guidance retains authority metadata.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-013 — Game Off deadline exception

- **Category:** source
- **Expected behavior:** Applicable organizer extension/exception can update readiness.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-014 — Devpost exact window

- **Category:** source
- **Expected behavior:** Timezone and legal age language are preserved.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-015 — Devpost eligibility schema

- **Category:** schema
- **Expected behavior:** Eligibility is a critical structured field.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-016 — Devpost rules completeness

- **Category:** schema
- **Expected behavior:** Deliverables, project requirements and prizes remain separate.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-017 — Devpost judging criteria

- **Category:** schema
- **Expected behavior:** Judging criteria do not become eligibility predicates.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-018 — Google FreeBusy

- **Category:** calendar
- **Expected behavior:** Busy intervals can be modeled without event titles.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-019 — Google recurrence

- **Category:** calendar
- **Expected behavior:** Recurring event semantics are preserved.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-020 — RFC5545 recurrence

- **Category:** calendar
- **Expected behavior:** RRULE/RDATE/EXDATE fixtures expand correctly.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-021 — CP-SAT capacity

- **Category:** solver
- **Expected behavior:** Candidate allocations respect capacity limits.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-022 — CP-SAT precedence

- **Category:** solver
- **Expected behavior:** Dependencies and non-overlap constraints hold.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-023 — Native PDF extraction

- **Category:** document
- **Expected behavior:** Native text extraction preserves page provenance.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-024 — OCR necessity/cost

- **Category:** document
- **Expected behavior:** Image-only text is routed to visual/OCR path.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-025 — Mixed PDF late fusion

- **Category:** document
- **Expected behavior:** Native and OCR candidate reports reconcile field-by-field.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-026 — OCR engine disagreement

- **Category:** document
- **Expected behavior:** OCR disagreement surfaces instead of being averaged away.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-027 — NIST trustworthy AI

- **Category:** governance
- **Expected behavior:** Reliability, transparency, privacy and oversight controls are traceable.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-028 — NIST explainability

- **Category:** governance
- **Expected behavior:** Displayed recommendations expose rationale and assumptions.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-029 — Time-management evidence

- **Category:** evidence
- **Expected behavior:** Research remains supporting context, not product-effectiveness proof.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.

## SE-030 — Timetable structure

- **Category:** calendar
- **Expected behavior:** Availability preserves temporal block structure rather than weekly-hour totals.
- **Pass condition:** Expected behavior is satisfied, relevant provenance/trace is preserved, and no unsupported fact is invented.


## Execution note
Live public pages must be snapshotted or hashed before a reproducible benchmark. Synthetic/rasterized derivatives may be used for document-path stress tests, but they remain fixtures rather than real-world product evidence.