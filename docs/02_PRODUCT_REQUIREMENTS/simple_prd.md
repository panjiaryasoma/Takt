# PRD Sederhana — Competition Decision Support System

**Versi:** 1.0  
**Tanggal:** 2026-09-21  
**Status:** baseline pre-production  
**Nama brand:** belum dikunci

## 1. Ringkasan produk

Aplikasi mobile-first decision support untuk orang yang mempertimbangkan atau mengerjakan kompetisi berbatas waktu.

Aplikasi membaca URL/PDF kompetisi, membangun canonical competition report dengan source provenance, memeriksa readiness/eligibility, mengestimasi pekerjaan, membandingkannya dengan kalender nyata pengguna, menghasilkan candidate work allocation yang feasible, lalu menyajikan recommendation, alternative, risk, assumption, dan trade-off.

Aplikasi tidak diam-diam menjadwalkan hidup pengguna.

## 2. Tujuan
1. Mengurangi rekonstruksi manual rules kompetisi.
2. Memunculkan eligibility/deadline blocker sebelum planning.
3. Membuat source conflict terlihat.
4. Mengubah requirement menjadi task dan workload range yang dapat diperiksa.
5. Menggunakan calendar constraint untuk menguji feasibility.
6. Merekomendasikan work window tanpa otomatis mengubahnya menjadi commitment.
7. Menjaga human authority pada consequential boundary.
8. Tetap berguna tanpa custom-trained ML.

## 3. Non-goals
- social network;
- teammate marketplace;
- autonomous registration/submission;
- automatic payment;
- automatic calendar modification;
- guaranteed completion prediction;
- generic life planner;
- generic Jira/Notion replacement;
- custom ML synthetic hanya untuk mengklaim "AI".

## 4. Persona utama

### P1 — Student builder
Punya kuliah, tugas, dan waktu kosong tidak teratur. Sulit menilai apakah kompetisi tambahan masih realistis.

### P2 — Working builder
Punya fixed work block dan capacity malam/weekend terbatas. Membutuhkan trade-off dan buffer visibility.

### P3 — Small team lead
Perlu mempertimbangkan availability beberapa anggota yang dimasukkan manual tanpa membutuhkan social discovery/chat.

## 5. Core user journey

### Journey A — Memahami opportunity
1. Pengguna paste URL atau upload PDF.
2. Backend melakukan ingestion web/PDF.
3. Native text dan visual/OCR pipeline menghasilkan candidate report independen.
4. Reconciliation menghasilkan canonical competition report.
5. Critical conflict/missing field ditampilkan untuk review.
6. Readiness triage mengembalikan status faktual.

### Journey B — Mengevaluasi feasibility
1. Sistem memecah confirmed requirements menjadi task/milestone.
2. Workload direpresentasikan min/likely/max.
3. Local calendar diubah menjadi busy/free block.
4. CP-SAT menghasilkan candidate allocation yang mematuhi hard constraint.
5. Recommendation layer melakukan ranking dan explanation.
6. Pengguna melihat feasibility state, suggested next work, alternative, risk, assumption, dan trade-off.

### Journey C — Menerima dan mengeksekusi
1. Pengguna menerima suggestion atau memilih alternative.
2. Accepted commitment dapat disimpan ke local plan.
3. Pengguna update progress.
4. Material change memicu re-evaluation, bukan silent mutation.

## 6. Information architecture

```text
HOME
├── My Schedule
│   ├── Calendar
│   └── Add Commitment
├── Analyze Competition
│   ├── Paste URL / Upload PDF
│   ├── Analysis Progress
│   ├── Competition Brief Review
│   └── Decision Support Report
└── Saved Plans
    ├── Competition Detail
    ├── Suggested Plan / Projection
    └── Progress / Re-evaluate
```

Identifier UI dapat diterjemahkan pada presentation layer tanpa mengubah kontrak internal.

## 7. Functional requirements

### FR-001 Personal commitments
Pengguna dapat membuat FIXED/FLEXIBLE commitment dengan date/time, recurrence, dan category.

### FR-002 Availability model
Sistem mengubah commitment menjadi available work block sambil mempertahankan timezone dan recurrence semantics.

### FR-003 Competition URL ingestion
Sistem menerima URL HTTP(S) dan mencatat retrieval metadata.

### FR-004 PDF ingestion
Sistem menerima PDF dan mencatat document/page provenance.

### FR-005 Dual-path extraction
FW1 native extraction dan FW2 visual/OCR dapat berjalan independen dan menghasilkan candidate-report schema yang sama.

### FR-006 Field-level reconciliation
Sistem merekonsiliasi normalized value, source authority, context, dan evidence. Confidence saja tidak boleh menyelesaikan critical conflict.

### FR-007 Canonical Competition Report
Menyimpan deadline, registration deadline, eligibility, team size, format/location, track, deliverable, judging criteria, required technology, prize/benefit, dan provenance.

### FR-008 Human source review
Critical field yang conflict, missing, atau evidence-nya lemah memerlukan review sebelum readiness.

### FR-009 Competition readiness triage
`READY_TO_EVALUATE`, `NEEDS_REVIEW`, `ELIGIBILITY_BLOCKED`, `DEADLINE_PASSED`, `INSUFFICIENT_INFORMATION`.

### FR-010 Task decomposition
Mengubah competition requirement menjadi candidate task, milestone, dependency, skill, dan submission work.

### FR-011 Workload estimation
Setiap task estimate berupa `min`, `likely`, `max` dengan basis yang dinyatakan.

### FR-012 Calendar-aware feasibility
Mengevaluasi workload terhadap real available block, bukan hanya total free hours.

### FR-013 CP-SAT candidate allocations
Solver menghasilkan candidate allocation yang feasible di bawah hard constraint. Output solver bukan automatic calendar commitment.

### FR-014 Recommendation layer
Melakukan ranking candidate dan menjelaskan next work, suggested window, alternative, buffer impact, dependency impact, dan assumption.

### FR-015 Feasibility states
`FEASIBLE`, `FEASIBLE_WITH_TRADEOFFS`, `TIGHT_CAPACITY`, `NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS`.

State ini menjelaskan modeled plan, bukan kemampuan personal pengguna.

### FR-016 Human decision
Pengguna dapat accept, choose alternative, edit constraint, atau ignore.

### FR-017 Accepted commitment
Hanya suggestion yang diterima eksplisit menjadi bagian local plan.

### FR-018 Progress
Pengguna dapat menandai work complete dan opsional mencatat actual effort.

### FR-019 Re-evaluation
Material change pada calendar, scope, deadline, task duration, atau team capacity menginvalidasi recommendation terdampak.

### FR-020 Saved plans
Pengguna dapat melihat saved competition, state terbaru, progress, risk, dan next recommendation.

### FR-021 Entitlement
RevenueCat boleh membatasi premium feature/capacity tetapi tidak boleh mengubah critical facts, eligibility, deadline, atau conflict warning.

### FR-022 Export
Pengguna dapat mengekspor explainable plan summary. Calendar write/export membutuhkan explicit action.

## 8. Canonical outputs
- `CompetitionBrief`: fakta grounded pada source.
- `ReadinessTriage`: factual deterministic gate.
- `WorkloadModel`: task + dependency + effort range.
- `CandidateAllocation[]`: feasible solver output.
- `Recommendation`: ranking/explanation atas candidate.
- `DecisionSupportReport`: brief + readiness + capacity + workload + feasibility + recommendation + alternative + risk + assumption + trade-off.

## 9. Data dan privacy

### Local-first
Utamakan local storage untuk event title/detail, routine label, accepted commitment, progress, dan saved plan cache.

### Cloud-minimized planning payload
Jika memungkinkan, backend menerima busy/free interval, timezone, daily capacity/preference, dan task model, bukan event name sensitif.

Local-first tidak otomatis berarti "private". Telemetry, backend request, crash reporting, dan third-party provider tetap harus didokumentasikan.

## 10. Penggunaan AI
AI/LLM cocok untuk structured extraction, contextual normalization, task decomposition, dan explanation drafting.

AI bukan authority untuk current time, arithmetic, deadline comparison, timezone conversion, hard eligibility setelah predicate diketahui, calendar collision, atau CP-SAT constraint satisfaction.

## 11. Deterministic engines
Schema validation, source-state machine, readiness triage, date/time normalization, recurrence expansion, availability calculation, CP-SAT candidate generation, hard-constraint validation, dan post-solver invariant checks.

## 12. Strategi mixed PDF
```text
PDF
├── FW1 native/structured extraction → CandidateReport A
└── FW2 visual/OCR extraction       → CandidateReport B
A + B → field-level reconciliation → Canonical Competition Report
```

Pertahankan page/source evidence dan conflict. OCR-only evidence boleh mengisi native-text gap. Critical disagreement tidak boleh diselesaikan hanya dengan confidence score.

## 13. Recommendation policy
Recommendation valid hanya jika memetakan ke solver candidate, seluruh hard constraint lolos, rationale menyebut faktor scheduling, assumption terlihat, dan alternative muncul ketika ada candidate materially berbeda.

## 14. Layar MVP
Home; My Schedule; Add Commitment; Analyze Competition; Analysis Progress; Competition Brief Review; Decision Support Report; Suggested Plan / Projection; Saved Plans; Competition Detail / Progress; Re-evaluation.

## 15. Hipotesis monetisasi
Potential Free: active competition terbatas, basic source analysis, satu current recommendation set, local schedule.

Potential Pro: lebih banyak active competition, advanced what-if analysis, alternatives, extended history, team-capacity modeling, export/history tools.

Ini **hipotesis**, bukan validated willingness-to-pay evidence.

## 16. Non-functional requirements

### Reliability
Nol hard-constraint violation pada valid recommendation; critical canonical field punya provenance.

### Explainability
Recommendation rationale/assumption dan conflict/missing state terlihat.

### Performance target MVP
Cached app terasa lokal; URL analysis target p50 <=15 detik untuk halaman biasa; PDF progress ditampilkan; re-evaluation tanpa source ingestion baru target p50 <=5 detik untuk task count normal.

### Accessibility
Primary action dapat ditap/klik; status tidak color-only; conflict/confidence readable; date/time ditampilkan sebagai text.

### Auditability
Persist source retrieval timestamp, extraction pipeline/version, canonical field provenance, rule version, solver configuration/version, dan recommendation basis.

## 17. Metrics
Gunakan metric di `evaluation_spec_v1.0.yaml`. Product metric setelah instrumentation mencakup analyze→brief-confirm, brief-confirm→decision-report, recommendation acceptance, alternative selection, re-evaluation, source-review, conflict frequency, user edit, dan estimate-vs-actual error.

Acceptance rate saja bukan proxy kualitas recommendation.

## 18. Launch gates
MVP hanya ready jika source suite lolos critical threshold, nol false-ready blocker, nol solver hard-constraint violation, critical field punya provenance, recommendation traceability lengkap, local/cloud privacy boundary terdokumentasi, dan entitlement tidak menyembunyikan critical warning.

## 19. Open decisions
Nama produk, mobile framework, backend hosting, LLM provider/model, OCR engine/ensemble, direct calendar integration, RevenueCat Free/Pro boundary, dan kedalaman team capacity V1.
