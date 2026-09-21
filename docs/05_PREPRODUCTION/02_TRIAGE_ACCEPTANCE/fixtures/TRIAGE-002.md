# TRIAGE-002 — Deadline passed

## Scenario
Authoritative deadline is earlier than evaluation time and no applicable authoritative extension exists.

## Expected
```yaml
status: DEADLINE_PASSED
```

## Acceptance
PASS only if the status is exact, reasons are traceable, no unsupported fact is invented, and the system does not decide whether the user should participate.

## Forbidden behavior
Do not continue as READY_TO_EVALUATE.

## Status
`SPECIFIED / NOT_YET_EXECUTED`
