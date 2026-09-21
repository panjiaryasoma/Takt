# Preproduction Second Brain

**Project:** Competition Decision Support System  
**Version:** 1.1  
**Date:** 2026-09-21

This directory is the pre-production reasoning package. It is deliberately stricter than a normal hackathon idea dump because "the AI will figure it out" remains a terrible data strategy.

## Folder map

```text
1_DISCOVERY_AND_PROBLEM/
  problem_brief.md
  discovery_real_world_evidence.md

2_PRODUCT_REQUIREMENTS/
  simple_prd.md
  PRD_SCHEMA_ALIGNMENT_ADDENDUM.md

3_EVALUATION_AND_DOMAIN_RULES/
  domain_rules_v1.0.yaml
  evaluation_matrix_v1.0.csv
  evaluation_spec_v1.0.yaml
  feature_schema_v1.0.yaml
  feature_traceability_v1.0.csv
  SOURCE_EVALUATION_SUITE_001-030.md
  SOURCE_SCHEMA.md
  validation_report.txt
  README_PREPRODUCTION_SECOND_BRAIN.md

4_DATA_STRATEGY/
  DATASET_STRATEGY.md
  SYNTHETIC_DATA_GENERATION_SPEC.yaml
  FEATURE_DEFINITION.md
  LABEL_POLICY.md
  DATA_LEAKAGE_RULES.md
  SPLIT_STRATEGY.md
  CALIBRATION_AND_UNCERTAINTY.md
  DATASET_ACCEPTANCE_CRITERIA.md
```

## Product invariants

- Decision support, not autonomous life scheduling.
- User retains consequential decision authority.
- Dual-path extraction precedes canonical reconciliation.
- Canonical critical fields carry provenance.
- Conflicts remain visible until resolved.
- Triage is deterministic and factual.
- CP-SAT returns candidate allocations, not commands.
- Recommendations expose reasons, assumptions and alternatives.
- Accepted commitment requires explicit user action.
- Monetization cannot corrupt critical correctness.
- Synthetic data cannot be treated as real-world product evidence.
- Custom ML cannot become decision authority without real held-out evaluation.

## Data status

### Real public source evidence
Used for extraction/reconciliation evaluation.

### Synthetic dataset
A prototype synthetic pack may exist separately. Its status is:

```text
EXPERIMENTAL
NOT SOURCE OF TRUTH
NOT FINAL TRAINING DATASET
```

The data-strategy documents in `4_DATA_STRATEGY/` take precedence over that prototype artifact.

### Real behavioral labels
Not yet collected.

## Change discipline

When changing a requirement: update PRD, feature schema if capability changes, domain rules if behavior changes, traceability, evaluation cases, data implications, then rerun validation.

When changing a canonical field: update `SOURCE_SCHEMA.md`, reconciliation cases, triage dependencies, task-decomposition dependencies, and source/feature definitions if needed.

When changing a model target or dataset: update label policy, feature definitions, leakage audit, split strategy, generation spec and acceptance criteria, then regenerate rather than patch labels by hand.

## Current pre-production verdict

**Continue pre-production. Do not lock the training dataset or start custom-model optimization yet.**

Current strengths:
- problem and workflow are grounded in real cases;
- source and canonical-report contracts exist;
- deterministic decision boundaries are explicit;
- evaluation suite and traceability exist;
- data-generation and leakage policy now exist.

Still open:
- final technical architecture;
- API contracts;
- concrete calendar data model;
- CP-SAT constraint schema;
- workload-estimation baseline;
- recommendation-ranking policy;
- executable test fixtures;
- user validation/usability study;
- RevenueCat entitlement boundary;
- real outcome-data collection plan.

The next artifact should come from those unresolved pre-production items rather than prematurely treating the prototype dataset as final.


## Contract and handoff extension

Pre-production now continues into:

```text
05_PREPRODUCTION/
  01_CONTRACTS_ACTIVE/
  02_TRIAGE_ACCEPTANCE/
  03_INTEGRATION_001/
  04_CLOSURE/

06_IMPLEMENTATION_HANDOFF/
```

`05_PREPRODUCTION/01_CONTRACTS_ACTIVE/` is the implementation-facing contract authority.

`06_IMPLEMENTATION_HANDOFF/` defines execution order and cut policy. It does not override behavioral contracts.
