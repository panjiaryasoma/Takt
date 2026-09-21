# README — Second Brain Triage Evaluation Suite

Suite triage menguji readiness, bukan menentukan apakah user sebaiknya ikut.

Allowed output:
- `READY_TO_EVALUATE`
- `NEEDS_REVIEW`
- `ELIGIBILITY_BLOCKED`
- `DEADLINE_PASSED`
- `INSUFFICIENT_INFORMATION`

Zero-tolerance failure: false READY pada expired/ineligible case, unknown attribute dianggap confirmed, critical conflict diselesaikan hanya dari confidence, mandatory data missing dianggap known, atau sistem mengeluarkan directive JOIN/DO_NOT_JOIN.
