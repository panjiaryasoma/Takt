# Addendum Penyelarasan Schema PRD

**Versi:** 1.0  
**Tanggal:** 2026-09-21

File ini menyelaraskan `simple_prd.md` dengan machine-readable schema dan evaluation asset. PRD prose sering terlihat jelas sampai dua engineer mengimplementasikan dua interpretasi berbeda, sebuah ritual industri yang rupanya belum punah.

## 1. Hierarki source of truth
1. `domain_rules_v1.0.yaml` — behavioral invariant.
2. `SOURCE_SCHEMA.md` — kontrak source, evidence, candidate report, canonical report.
3. `feature_schema_v1.0.yaml` — historical feature inventory/release boundary.
4. `simple_prd.md` — product intent dan user-facing requirement.
5. `evaluation_spec_v1.0.yaml` — acceptance methodology.
6. `evaluation_matrix_v1.0.csv` — executable pre-production case inventory.

Jika prose bertentangan dengan critical domain invariant, domain rule berlaku sampai ada versioned change yang eksplisit.

## 2. PRD → feature alignment

| Area PRD | Canonical feature IDs |
|---|---|
| Kalender personal | F-001, F-002 |
| URL/PDF intake | F-003, F-004 |
| Dual-path extraction | F-005, F-006, F-007 |
| Reconciliation/canonical report | F-008, F-009 |
| Competition readiness | F-010 |
| Task/workload modeling | F-011, F-012 |
| Constraint model + CP-SAT | F-013, F-014 |
| Recommendation/decision support | F-015, F-016, F-017 |
| Accepted commitment/progress | F-018, F-019, F-020, F-021 |
| Monetization | F-022 |
| Export/calendar integration | F-023, F-024 |
| Future learned effort adjustment | F-025 |

## 3. Core data contracts
- Source ingestion: `SourceRecord[] + EvidenceSpan[]`
- Extraction: `CandidateExtractionReport`, FW1/FW2 setara dan belum canonical.
- Reconciliation: `CanonicalCompetitionReport`
- Readiness: `READY_TO_EVALUATE | NEEDS_REVIEW | ELIGIBILITY_BLOCKED | DEADLINE_PASSED | INSUFFICIENT_INFORMATION`
- Workload: task dengan dependency dan min/likely/max.
- Candidate allocation: candidate, work blocks, buffer, hard violations, assumption.
- Recommendation: candidate reference, suggested windows, alternatives, rationale, trade-offs, assumption.

Recommendation `null` valid jika evidence atau feasibility tidak cukup.

## 4. Pemisahan state
Source extraction confidence, canonical verification, readiness, feasibility, recommendation ranking, dan human acceptance tidak boleh dilebur.

High-confidence OCR bukan `VERIFIED`; `READY_TO_EVALUATE` bukan `FEASIBLE`; `FEASIBLE` bukan "pengguna sebaiknya ikut".

## 5. Bahasa decision support
Diperbolehkan: "Feasible di bawah asumsi saat ini", "Kapasitas ketat", recommended work window, alternative, dan explicit buffer/trade-off.

Dilarang sebagai conclusion sistem: "Kamu pasti harus ikut", "Kamu tidak bisa melakukan ini" ketika hanya current constraints yang infeasible, "Ini kompetisi terbaik untukmu", atau "Kamu harus bekerja jam 19:00".

## 6. PDF late-fusion alignment
`FR-005` mewajibkan independent candidate report dan reconciliation setelah kedua report. Page/region optimization boleh dilakukan tanpa mengubah contract.

## 7. Calendar alignment
Bedakan FIXED, FLEXIBLE, FREE, accepted competition commitment, dan suggested work window. Hanya accepted commitment yang masuk committed plan.

## 8. Evaluation alignment
Semua FR-001..FR-022 harus traceable. Critical invariant: zero false READY known blocker; zero CP-SAT hard violation; 100% provenance critical fields; 100% recommendation-to-candidate traceability; zero silent external/calendar action.

## 9. Deferred decisions
LLM vendor/model, OCR engine, mobile framework, cloud vendor, dan paid-tier limit tidak dikunci kecuali mengubah product behavior/evaluation contract.

## 10. Data-strategy alignment
Synthetic data valid untuk engineering dan deterministic/adversarial evaluation. Synthetic-only predictive performance bukan product evidence. MVP tetap valid tanpa custom-trained ML.
