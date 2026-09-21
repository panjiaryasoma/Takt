# TRIAGE-003 — Eligibility blocked

## Skenario
Official rules require enrolled students and the user is explicitly known not to be enrolled.

## Expected
```yaml
status: ELIGIBILITY_BLOCKED
```

## Acceptance
PASS jika status tepat, reason dapat ditelusuri, tidak ada unsupported fact, dan sistem tidak memutuskan apakah user harus ikut.

## Perilaku dilarang
Do not downgrade the blocker to a warning.

## Status
`SPECIFIED / NOT_YET_EXECUTED`
