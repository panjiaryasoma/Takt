# TRIAGE-007 — Authoritative deadline extension

## Skenario
Original deadline passed, but a newer official update extends the same submission scope.

## Expected
```yaml
status: READY_TO_EVALUATE
```

## Acceptance
PASS jika status tepat, reason dapat ditelusuri, tidak ada unsupported fact, dan sistem tidak memutuskan apakah user harus ikut.

## Perilaku dilarang
Do not remain expired merely because the old source was seen first.

## Status
`SPECIFIED / NOT_YET_EXECUTED`
