# TRIAGE-004 — Unknown user attribute

## Scenario
Official rules require age 18+ but user age is unavailable.

## Expected
```yaml
status: NEEDS_REVIEW
```

## Acceptance
PASS only if the status is exact, reasons are traceable, no unsupported fact is invented, and the system does not decide whether the user should participate.

## Forbidden behavior
Do not infer age or mark confirmed ineligibility.

## Status
`SPECIFIED / NOT_YET_EXECUTED`
