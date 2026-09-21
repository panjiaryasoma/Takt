# TRIAGE-008 — Scoped category rule

## Scenario
General event is broad; selected student category requires current enrollment and the user is confirmed student.

## Expected
```yaml
status: READY_TO_EVALUATE
```

## Acceptance
PASS only if the status is exact, reasons are traceable, no unsupported fact is invented, and the system does not decide whether the user should participate.

## Forbidden behavior
Do not discard category-specific scope or create a false conflict.

## Status
`SPECIFIED / NOT_YET_EXECUTED`
