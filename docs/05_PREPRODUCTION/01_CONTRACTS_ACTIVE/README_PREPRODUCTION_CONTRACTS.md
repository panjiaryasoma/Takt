# README — Preproduction Contracts

This folder contains the active implementation-facing behavioral contracts.

Read order:
1. `BASELINE_CONTRACT.md`
2. `SCHEMA_FINALIZATION_DECISION.md`
3. `FEATURE_SCHEMA_FINAL.yaml`
4. `SCHEMA_CHANGE_REQUEST_001.md`
5. `SCHEMA_CHANGE_REQUEST_002.md`
6. `SCHEMA_CHANGE_REQUEST_003.md`
7. `SCHEMA_CHANGE_REQUEST_004.md`
8. `TOOLCHAIN_DECISION.md`
9. `SCHEMA_SUPERSESSION_NOTICE.md`

Authority:
```text
BASELINE_CONTRACT
+ FEATURE_SCHEMA_FINAL
+ approved schema change requests
+ domain_rules_v1.0.yaml
→ implementation
```

Frozen: status enums, authority boundaries, canonical-source behavior, triage semantics, solver-output semantics, recommendation/human-commit boundary.

Not frozen: visual design, internal class names, cloud vendor, LLM provider, OCR engine, performance tuning.
