# TRIAGE-004 — Unknown user attribute

## Skenario
Official rules require age 18+ but user age is unavailable.

## Expected
```yaml
status: NEEDS_REVIEW
```

## Acceptance
PASS jika status tepat, reason dapat ditelusuri, tidak ada unsupported fact, dan sistem tidak memutuskan apakah user harus ikut.

## Perilaku dilarang
Do not infer age or mark confirmed ineligibility.

## Status
`SPECIFIED / NOT_YET_EXECUTED`
