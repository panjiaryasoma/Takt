# README — Triage Evaluation Suite Second Brain

The triage suite tests readiness, not whether the user should join.

Unit under test:
```text
CanonicalCompetitionReport
+ known user attributes
+ current time
→ ReadinessTriage
```

Allowed outputs:
- `READY_TO_EVALUATE`
- `NEEDS_REVIEW`
- `ELIGIBILITY_BLOCKED`
- `DEADLINE_PASSED`
- `INSUFFICIENT_INFORMATION`

Zero-tolerance failures include false READY on expired/ineligible cases, unknown attributes treated as confirmed facts, confidence-only critical-conflict resolution, missing mandatory data treated as known, and personal JOIN/DO_NOT_JOIN directives.
