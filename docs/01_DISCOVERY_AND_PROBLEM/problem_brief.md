# Problem Brief — Competition Decision Support System

**Version:** 1.0  
**Date:** 2026-09-21  
**Working title:** intentionally not locked  
**Product class:** Calendar-aware competition decision support  
**Primary target:** Students and early-career builders who participate in hackathons, challenges, competitions, or time-bounded build programs.

## 1. Problem statement

Competition information and a participant's real-life schedule live in separate systems.

A competition page describes deadlines, eligibility, deliverables, team constraints, judging criteria, mandatory technologies, and submission rules. A calendar describes classes, work, routines, exams, existing commitments, and free time. The participant must mentally combine both and answer a harder question:

> Given the opportunity requirements and the time I actually have, what is feasible, what should I work on next, and what trade-offs am I accepting?

Existing calendars can expose free/busy time but do not understand competition rules. Competition platforms expose rules but do not reason over the participant's real calendar. Generic project-management tools assume the project already exists and usually require the user to create tasks and timelines manually.

The proposed product joins those domains without taking decision authority away from the user.

## 2. Product thesis

The product should **not** automatically schedule a user's life or decide whether they should join a competition.

It should:
1. ingest a competition source (URL and/or PDF);
2. produce a provenance-preserving canonical competition report;
3. deterministically triage whether the opportunity is ready to evaluate;
4. decompose requirements into candidate work;
5. estimate workload as ranges, not false-precision point estimates;
6. model the user's available time from their calendar;
7. generate feasible candidate allocations under hard constraints;
8. turn those allocations into recommendations, alternatives, assumptions, and trade-offs;
9. leave acceptance, rejection, and calendar commitment to the human.

**Core principle:** AI interprets ambiguous information; deterministic systems verify and constrain; the human decides.

## 3. Evidence status

### Known
- Competition eligibility can contain material restrictions that participants need to know before investing work. Devpost's organizer guidance explicitly treats eligibility as a first-class rules concern. See `SRC-015`.
- Real competition requirements are heterogeneous. Shipaton, Swift Student Challenge, Imagine Cup, HackMIT, GitHub Game Off, and GitLab's Devpost challenge vary on team size, age/student status, required technology, artifact types, store/repository obligations, and deadlines. See `SRC-001`–`SRC-014`.
- Deadlines are timezone-sensitive and can be expressed in multiple formats. See `SRC-001`, `SRC-006`, `SRC-010`, and `SRC-014`.
- Calendar systems can expose free/busy intervals without requiring the planner to consume event titles. See `SRC-018`.
- Recurring commitments require explicit recurrence and exception semantics. See `SRC-019` and `SRC-020`.
- Constraint programming is suitable for precedence, non-overlap, capacity, and preference-aware scheduling problems. See `SRC-021` and `SRC-022`.
- Mixed PDFs can contain native text and image-only content. PyMuPDF/PyMuPDF4LLM provide separate text, image, and OCR paths. See `SRC-023`–`SRC-026`.
- Explainability and human oversight are important when AI outputs affect user decisions. See `SRC-027` and `SRC-028`.

### Suspected, but supported
- Calendar-aware recommendations should be more useful than a simple `hours remaining >= estimated hours` check because timetable structure affects behavior and because contiguous work blocks differ from fragmented free time. `SRC-029` and `SRC-030` support the importance of time-management/timetable structure but do **not** prove this product's effectiveness.
- Users may benefit from seeing alternatives and trade-offs rather than one final schedule. This follows from the decision-support framing and human-oversight requirement, but requires product evaluation.

### Not yet demonstrated
- Users will pay for advanced recommendations or multi-competition planning.
- Custom ML will outperform deterministic heuristics for effort estimation before sufficient historical user data exists.
- The product improves competition completion rate, submission quality, or stress.
- A recommendation engine will be trusted merely because it explains itself.
- Team-capacity recommendations materially improve outcomes without richer teammate availability data.

These are hypotheses, not marketing claims.

## 4. Primary user job

> When I find a competition, help me understand what it really requires and how it could fit around my actual commitments, so I can make an informed decision and act without manually reconstructing the rules and schedule.

## 5. Scope

### In scope for MVP
- manual personal schedule / commitments;
- URL ingestion;
- PDF upload;
- independent native-text and visual/OCR extraction paths;
- candidate extraction reports with identical schema;
- field-level reconciliation into a canonical competition report;
- source provenance for critical fields;
- competition-readiness triage;
- task/dependency generation;
- effort ranges;
- calendar-aware availability model;
- CP-SAT candidate allocations;
- recommendation + alternatives + trade-offs;
- human approval before any accepted commitment;
- saved plans and progress;
- re-evaluation when constraints materially change;
- RevenueCat entitlement gating appropriate to Shipaton.

### Explicitly out of scope for MVP
- social feed;
- teammate marketplace;
- automatic team formation;
- autonomous registration/submission;
- autonomous payment;
- silent calendar writes;
- automatic scope reduction without user approval;
- pretending feasibility is certainty;
- custom ML trained on invented or insufficient outcome data.

## 6. Failure modes to design against
1. Wrong deadline with high confidence.
2. Eligibility rule missed, causing work on an ineligible competition.
3. OCR overrides correct native text without provenance.
4. Native text ignores information embedded in an image.
5. Conflicting official pages silently collapsed into one value.
6. Timezone conversion changes the effective local day.
7. Recurring class/work events treated as one-off.
8. Free hours counted but fragmented into unusable micro-blocks.
9. Solver output presented as a command rather than a candidate.
10. Recommendation cannot explain why it exists.
11. User edits a constraint but stale recommendations remain visible.
12. RevenueCat gating changes the correctness of eligibility or critical facts.

## 7. Success definition for pre-production

Pre-production is ready to proceed when:
- domain rules are explicit and machine-readable;
- source schema supports provenance and conflict preservation;
- every MVP feature traces to a requirement, domain rule, and evaluation case;
- critical-field extraction and reconciliation have measurable acceptance criteria;
- triage has zero-tolerance safety invariants for expired/ineligible cases in the evaluation suite;
- CP-SAT candidate generation has zero hard-constraint violations in test fixtures;
- recommendation output is advisory and traceable to candidate allocations;
- open product hypotheses are labeled as hypotheses rather than facts.

## 8. Primary sources

See `3_EVALUATION_AND_DOMAIN_RULES/SOURCE_EVALUATION_SUITE_001-030.md` for the 30-source evaluation suite and `SOURCE_SCHEMA.md` for source/canonical-report contracts.
