# Kriteria Acceptance Dataset

**Version:** 1.0

Dataset tidak otomatis diterima hanya karena jumlah barisnya banyak.

## Universal checks
Document purpose, schema, generation/collection method, source/synthetic status, version, row count, target definition, feature availability stage, missing-value policy, split policy, leakage audit, limitations and reproducibility metadata.

## Synthetic fixture acceptance
Require implemented generation spec, fixed seed, generator version, reproducible row counts, domain-rule alignment, documented target formula, leakage tags, class distribution report, clearly marked balanced views, deterministic edge cases and passing validation.

Required coverage:
- calendar recurrence, exception, overlap, zero capacity, fragmentation, long focus block, cross-midnight;
- reconciliation agreement, native-only, OCR-only, critical conflict, contextual conflict, duplicate evidence, multiple-official-source conflict;
- feasibility clear-feasible, trade-off, tight, infeasible, dependency bottleneck, buffer exhaustion, daily-cap violation.

## Real source corpus
Require authoritative source identity, retrieval timestamp, snapshot/hash, manually verified critical gold fields, evidence locator, freshness policy and duplicate-family handling.

## Real behavioral dataset
Before model claims: document consent/data use, stable collection procedure, measured target, sample rationale, population, missingness, grouping, leakage audit and baselines.

## Model-readiness gate
```text
schema pass
+ label-policy pass
+ leakage-audit pass
+ split-strategy pass
+ baseline defined
+ metric defined
```

For synthetic-only data:
```text
MODEL PIPELINE READY != MODEL REAL-WORLD VALIDATED
```

## Current status
- Real source corpus: pre-production evaluation corpus exists.
- Synthetic fixture pack: prototype / experimentation only.
- Real effort history: not yet available.
- Real recommendation-quality labels: not yet available.
- Custom ML: not authorized as MVP decision authority.
