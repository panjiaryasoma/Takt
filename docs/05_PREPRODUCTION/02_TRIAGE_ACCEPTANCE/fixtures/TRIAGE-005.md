# TRIAGE-005 — Critical deadline conflict

## Scenario
Two deadline candidates remain unresolved in the canonical report.

## Expected
```yaml
status: NEEDS_REVIEW
```

## Acceptance
PASS only if the status is exact, reasons are traceable, no unsupported fact is invented, and the system does not decide whether the user should participate.

## Forbidden behavior
Do not choose the higher-confidence extractor result.

## Status
`SPECIFIED / NOT_YET_EXECUTED`
