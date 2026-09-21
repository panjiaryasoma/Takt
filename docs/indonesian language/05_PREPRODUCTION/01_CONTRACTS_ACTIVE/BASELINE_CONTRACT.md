# Kontrak Baseline

**Versi:** 1.0  
**Status:** BASELINE PRE-PRODUCTION AKTIF

## Kontrak produk
Produk adalah calendar-aware competition decision-support system. Sistem memahami source kompetisi, mempertahankan provenance, menampilkan ambiguity/conflict, menjalankan readiness secara deterministik, mengurai workload, memodelkan kapasitas nyata, menghasilkan candidate allocation yang feasible, menjelaskan recommendation/trade-off, dan mempertahankan keputusan konsekuensial pada user.

## Batas kewenangan
AI/LLM boleh melakukan extraction, normalization, task-decomposition proposal, dan draf explanation.

Sistem deterministik wajib menangani schema validation, date/time/timezone, triage, calendar/dependency constraints, CP-SAT verification, dan stale-recommendation invalidation.

Manusia tetap menentukan koreksi source, keputusan ikut/tidak, scope acceptance, recommendation acceptance, calendar commitment, submission, payment, dan tindakan eksternal.

## Kontrak source
```text
SourceRecord[]
→ CandidateExtractionReport(s)
→ Field-Level Reconciliation
→ CanonicalCompetitionReport
```

Critical field wajib punya provenance. Conflict kritis yang unresolved tetap terlihat.

## Readiness
- `READY_TO_EVALUATE`
- `NEEDS_REVIEW`
- `ELIGIBILITY_BLOCKED`
- `DEADLINE_PASSED`
- `INSUFFICIENT_INFORMATION`

Readiness adalah factual gate, bukan keputusan JOIN/DO_NOT_JOIN.

## Feasibility
- `FEASIBLE`
- `FEASIBLE_WITH_TRADEOFFS`
- `TIGHT_CAPACITY`
- `NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS`

State menjelaskan modeled plan di bawah constraint saat ini, bukan kemampuan personal user.

## Solver
CP-SAT menghasilkan `CandidateAllocation[]`, bukan final calendar. Candidate yang dapat direkomendasikan harus zero hard-constraint violation.

## Recommendation
Recommendation wajib traceable ke candidate valid dan menampilkan rationale, assumptions, trade-offs, serta alternatives jika tersedia.

## Data dan monetization
Synthetic data bukan real-world product evidence. RevenueCat tidak boleh mengubah correctness-critical truth.

## Change control
Perubahan semantik pada schema/status/authority/triage/hard constraint/recommendation wajib memakai versioned change request.
