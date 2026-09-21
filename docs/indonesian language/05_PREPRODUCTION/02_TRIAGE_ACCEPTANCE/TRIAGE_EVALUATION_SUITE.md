# Triage Evaluation Suite

**Version:** 1.0  
**Jumlah fixture:** 8  
**Status eksekusi:** SPECIFIED / NOT_YET_EXECUTED

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

Semua 8 fixture wajib lolos. Critical false-ready failure memblokir acceptance modul triage.
