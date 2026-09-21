# INTEGRATION-001

## Goal
Validate:
```text
CanonicalCompetitionReport
+ user attributes
+ domain rules
→ ReadinessTriage
→ planning gate
```

The fixture intentionally begins after source extraction.

## Acceptance
1. schema validation succeeds;
2. triage returns exactly `READY_TO_EVALUATE`;
3. critical evidence references remain present;
4. no user-choice directive is emitted;
5. planning gate opens;
6. result is reproducible for the same rule version.

**Status:** `SPECIFIED / NOT_YET_EXECUTED`
