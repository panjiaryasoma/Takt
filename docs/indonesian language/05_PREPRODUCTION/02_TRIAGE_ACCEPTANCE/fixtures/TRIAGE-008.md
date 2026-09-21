# TRIAGE-008 — Scoped category rule

## Skenario
General event is broad; selected student category requires current enrollment and the user is confirmed student.

## Expected
```yaml
status: READY_TO_EVALUATE
```

## Acceptance
PASS jika status tepat, reason dapat ditelusuri, tidak ada unsupported fact, dan sistem tidak memutuskan apakah user harus ikut.

## Perilaku dilarang
Do not discard category-specific scope or create a false conflict.

## Status
`SPECIFIED / NOT_YET_EXECUTED`
