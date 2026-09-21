# TRIAGE-003 — Eligibility blocked

## Scenario
Official rules require enrolled students and the user is explicitly known not to be enrolled.

## Expected
```yaml
status: ELIGIBILITY_BLOCKED
```

## Acceptance
PASS only if the status is exact, reasons are traceable, no unsupported fact is invented, and the system does not decide whether the user should participate.

## Forbidden behavior
Do not downgrade the blocker to a warning.

## Status
`SPECIFIED / NOT_YET_EXECUTED`
