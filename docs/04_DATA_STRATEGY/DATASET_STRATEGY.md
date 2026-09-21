# Dataset Strategy

**Version:** 1.0  
**Status:** Pre-production specification

## Purpose
Data policy must precede training-data freeze. The project must not generate a convenient dataset, obtain an impressive score, and then retrofit methodology around it.

## Data classes

### Real public source corpus
Used for competition URL/PDF extraction, canonical-field validation, provenance, and conflict evaluation. It is evaluation evidence, not a custom-model training dataset.

### Synthetic deterministic/adversarial fixtures
Used for calendar constraints, recurrence, CP-SAT invariants, native-vs-OCR reconciliation, missing/conflicting-source states, and other reproducible edge cases.

### Real behavioral/outcome data
Required later for learned effort estimation, estimate-bias calibration, recommendation usefulness, acceptance behavior, and completion-risk modeling.

## Dataset families
- **DS-01 Source Understanding Corpus:** real authoritative sources + controlled derivatives; manually verified critical fields.
- **DS-02 Calendar Constraint Fixtures:** deterministic schedule and recurrence fixtures.
- **DS-03 Solver Feasibility Fixtures:** task/dependency/capacity/buffer cases with invariant-based truth.
- **DS-04 Task Effort Dataset:** synthetic for prototype engineering; real estimate-vs-actual history required before production claims.
- **DS-05 Recommendation Evaluation Dataset:** real user evaluation; synthetic acceptance labels are not evidence of recommendation quality.

## Source hierarchy
1. official legal/rules source;
2. official organizer source;
3. official event/platform page;
4. official FAQ/update;
5. secondary source;
6. synthetic fixture, evaluation only.

## Custom-model training gate
Training is permitted only when target definition is stable, prediction-time features are documented, leakage audit passes, split strategy is locked, baselines and metrics are defined, sufficient real labels exist, uncertainty/calibration plan exists, deterministic rules remain authoritative, and rollback is possible.

## MVP decision
Use pretrained LLM/OCR + deterministic reconciliation, rules for readiness, CP-SAT for feasibility, transparent heuristic ranking for recommendations, and user-adjustable effort ranges. A custom-trained ML model is not required for MVP.

## Current synthetic pack status
```text
EXPERIMENTAL
NOT SOURCE OF TRUTH
NOT FINAL TRAINING DATASET
NOT PRODUCT EVIDENCE
```
