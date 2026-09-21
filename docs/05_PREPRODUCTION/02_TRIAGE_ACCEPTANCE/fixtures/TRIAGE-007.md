# TRIAGE-007 — Authoritative deadline extension

## Scenario
Original deadline passed, but a newer official update extends the same submission scope.

## Expected
```yaml
status: READY_TO_EVALUATE
```

## Acceptance
PASS only if the status is exact, reasons are traceable, no unsupported fact is invented, and the system does not decide whether the user should participate.

## Forbidden behavior
Do not remain expired merely because the old source was seen first.

## Status
`SPECIFIED / NOT_YET_EXECUTED`
