# Triage Evaluation Suite

**Version:** 1.0  
**Fixtures:** 8  
**Execution status:** SPECIFIED / NOT_YET_EXECUTED

| Fixture | Scenario | Expected |
|---|---|---|
| TRIAGE-001 | Ready baseline | `READY_TO_EVALUATE` |
| TRIAGE-002 | Deadline passed | `DEADLINE_PASSED` |
| TRIAGE-003 | Eligibility blocked | `ELIGIBILITY_BLOCKED` |
| TRIAGE-004 | Unknown user attribute | `NEEDS_REVIEW` |
| TRIAGE-005 | Critical deadline conflict | `NEEDS_REVIEW` |
| TRIAGE-006 | Mandatory deliverable information missing | `INSUFFICIENT_INFORMATION` |
| TRIAGE-007 | Authoritative deadline extension | `READY_TO_EVALUATE` |
| TRIAGE-008 | Scoped category rule | `READY_TO_EVALUATE` |

All 8 fixtures are required. Any critical false-ready failure blocks triage acceptance.
