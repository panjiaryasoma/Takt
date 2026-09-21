# Production Task Order v1.0 — Draft

| Order | Work | Dependency | Exit |
|---:|---|---|---|
| 01 | repo/bootstrap/contracts | none | schemas load |
| 02 | triage engine | 01 | TRIAGE-001..008 pass |
| 03 | source record + candidate report types | 01 | schema tests pass |
| 04 | native web/PDF ingestion | 03 | source fixture parsed |
| 05 | OCR adapter | 03 | OCR fixture parsed |
| 06 | reconciliation | 04,05 | conflicts preserved |
| 07 | INTEGRATION-001 | 02,06 | integration green |
| 08 | schedule/local persistence | 01 | commitment CRUD works |
| 09 | availability model | 08 | calendar fixtures pass |
| 10 | task/workload model | 06 | ranges/dependencies emitted |
| 11 | CP-SAT candidate solver | 09,10 | hard invariants pass |
| 12 | recommendation layer | 11 | traceable option + alternative |
| 13 | mobile decision-report flow | 07,12 | vertical slice works |
| 14 | saved plan/progress/re-evaluate | 13 | stale invalidation works |
| 15 | RevenueCat | 13 | entitlement cannot alter correctness |
| 16 | demo hardening | all P0 | repeatable demo |
| 17 | P1 extras | P0 green | only if deadline permits |

Jangan mulai custom ML sebelum core demo stabil kecuali kondisi real-data berubah secara material.
