# TRIAGE-005 — Critical deadline conflict

## Skenario
Two deadline candidates remain unresolved in the canonical report.

## Expected
```yaml
status: NEEDS_REVIEW
```

## Acceptance
PASS jika status tepat, reason dapat ditelusuri, tidak ada unsupported fact, dan sistem tidak memutuskan apakah user harus ikut.

## Perilaku dilarang
Do not choose the higher-confidence extractor result.

## Status
`SPECIFIED / NOT_YET_EXECUTED`
