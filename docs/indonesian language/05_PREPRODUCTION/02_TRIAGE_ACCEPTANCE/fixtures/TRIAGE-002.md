# TRIAGE-002 — Deadline passed

## Skenario
Authoritative deadline is earlier than evaluation time and no applicable authoritative extension exists.

## Expected
```yaml
status: DEADLINE_PASSED
```

## Acceptance
PASS jika status tepat, reason dapat ditelusuri, tidak ada unsupported fact, dan sistem tidak memutuskan apakah user harus ikut.

## Perilaku dilarang
Do not continue as READY_TO_EVALUATE.

## Status
`SPECIFIED / NOT_YET_EXECUTED`
