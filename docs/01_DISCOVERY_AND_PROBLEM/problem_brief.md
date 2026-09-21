# Ringkasan Masalah — Competition Decision Support System

**Versi:** 1.0  
**Tanggal:** 2026-09-21  
**Judul kerja:** sengaja belum dikunci  
**Kelas produk:** decision support kompetisi yang sadar kalender  
**Target utama:** mahasiswa dan builder tahap awal karier yang mengikuti hackathon, challenge, kompetisi, atau program pembangunan produk dengan batas waktu.

## 1. Pernyataan masalah

Informasi kompetisi dan jadwal kehidupan nyata peserta berada di sistem yang terpisah.

Halaman kompetisi menjelaskan deadline, eligibility, deliverable, batasan tim, kriteria penilaian, teknologi wajib, dan aturan submission. Kalender menjelaskan kuliah, pekerjaan, rutinitas, ujian, komitmen yang sudah ada, serta waktu kosong. Peserta harus menggabungkan keduanya secara mental untuk menjawab pertanyaan yang lebih sulit:

> Dengan requirement opportunity ini dan waktu yang benar-benar saya punya, apa yang feasible, apa yang sebaiknya saya kerjakan berikutnya, dan trade-off apa yang saya terima?

Kalender dapat menunjukkan free/busy time tetapi tidak memahami rules kompetisi. Platform kompetisi menyediakan rules tetapi tidak menalar terhadap kalender nyata peserta. Tool project-management generik biasanya menganggap proyek sudah ada dan meminta pengguna membuat task/timeline secara manual.

Produk yang diusulkan menghubungkan kedua domain tersebut tanpa mengambil otoritas keputusan dari pengguna.

## 2. Tesis produk

Produk **tidak** boleh otomatis menjadwalkan hidup pengguna atau memutuskan apakah pengguna harus mengikuti sebuah kompetisi.

Produk harus:
1. menerima sumber kompetisi berupa URL dan/atau PDF;
2. menghasilkan canonical competition report yang mempertahankan provenance;
3. melakukan triage deterministik untuk menentukan apakah opportunity siap dievaluasi;
4. memecah requirement menjadi candidate work;
5. mengestimasi workload sebagai range, bukan angka tunggal dengan presisi palsu;
6. memodelkan waktu tersedia dari kalender pengguna;
7. menghasilkan candidate allocation yang feasible di bawah hard constraints;
8. mengubah candidate tersebut menjadi recommendation, alternative, assumption, dan trade-off;
9. menyerahkan acceptance, rejection, dan calendar commitment kepada manusia.

**Prinsip inti:** AI menginterpretasikan informasi ambigu; sistem deterministik memverifikasi dan membatasi; manusia memutuskan.

## 3. Status bukti

### Diketahui
- Eligibility dapat memiliki pembatas material yang perlu diketahui peserta sebelum menginvestasikan waktu (`SRC-015`).
- Requirement kompetisi nyata sangat heterogen pada team size, usia/status mahasiswa, required technology, artifact, store/repository obligation, dan deadline (`SRC-001`–`SRC-014`).
- Deadline sensitif terhadap timezone dan format (`SRC-001`, `SRC-006`, `SRC-010`, `SRC-014`).
- Sistem kalender dapat mengekspos free/busy interval tanpa event title (`SRC-018`).
- Recurring commitment membutuhkan recurrence dan exception semantics (`SRC-019`, `SRC-020`).
- Constraint programming cocok untuk precedence, non-overlap, capacity, dan preference-aware scheduling (`SRC-021`, `SRC-022`).
- Mixed PDF dapat berisi native text sekaligus image-only content (`SRC-023`–`SRC-026`).
- Explainability dan human oversight penting ketika AI memengaruhi keputusan (`SRC-027`, `SRC-028`).

### Diduga, tetapi didukung
- Calendar-aware recommendation kemungkinan lebih berguna daripada hanya membandingkan total jam, karena contiguous block berbeda dari free time yang terfragmentasi (`SRC-029`, `SRC-030`). Bukti ini **tidak** membuktikan efektivitas produk.
- Pengguna mungkin mendapat manfaat dari alternative dan trade-off daripada satu final schedule, tetapi tetap memerlukan product evaluation.

### Belum terbukti
- Pengguna akan membayar untuk advanced recommendation atau multi-competition planning.
- Custom ML akan mengalahkan deterministic heuristic sebelum real historical data cukup.
- Produk meningkatkan completion rate, submission quality, atau mengurangi stres.
- Recommendation engine akan dipercaya hanya karena explainable.
- Team-capacity recommendation meningkatkan outcome tanpa teammate availability data yang lebih kaya.

Semua poin tersebut adalah hipotesis, bukan klaim marketing.

## 4. Primary user job

> Ketika saya menemukan kompetisi, bantu saya memahami requirement sebenarnya dan bagaimana opportunity itu dapat masuk ke komitmen nyata saya, supaya saya bisa mengambil keputusan dengan informasi cukup tanpa merekonstruksi rules dan jadwal secara manual.

## 5. Scope

### Masuk scope MVP
- manual personal schedule/commitment;
- URL ingestion;
- PDF upload;
- independent native-text dan visual/OCR path;
- candidate extraction report dengan schema identik;
- field-level reconciliation menjadi canonical competition report;
- source provenance untuk critical field;
- competition-readiness triage;
- task/dependency generation;
- effort range;
- calendar-aware availability model;
- CP-SAT candidate allocation;
- recommendation + alternative + trade-off;
- human approval sebelum accepted commitment;
- saved plans dan progress;
- re-evaluation saat constraint berubah material;
- RevenueCat entitlement gating yang sesuai kebutuhan Shipaton.

### Secara eksplisit di luar scope MVP
- social feed;
- teammate marketplace;
- automatic team formation;
- autonomous registration/submission;
- autonomous payment;
- silent calendar write;
- automatic scope reduction tanpa persetujuan;
- memperlakukan feasibility sebagai kepastian;
- custom ML dari invented/insufficient outcome data.

## 6. Failure mode yang harus dicegah
1. Deadline salah tetapi confidence tinggi.
2. Eligibility rule terlewat.
3. OCR menimpa native text benar tanpa provenance.
4. Native text mengabaikan informasi penting pada image.
5. Conflicting official pages diam-diam dilebur menjadi satu nilai.
6. Timezone conversion mengubah hari lokal secara salah.
7. Recurring event diperlakukan one-off.
8. Free hours cukup secara total tetapi terfragmentasi menjadi micro-block tidak berguna.
9. Solver output ditampilkan sebagai perintah, bukan candidate.
10. Recommendation tidak dapat menjelaskan alasannya.
11. Constraint berubah tetapi stale recommendation tetap tampil.
12. RevenueCat gating mengubah eligibility atau critical facts.

## 7. Definisi keberhasilan pre-production

Pre-production siap dilanjutkan ketika domain rules machine-readable; source schema mempertahankan provenance/conflict; fitur MVP traceable ke requirement/rule/evaluation; critical extraction/reconciliation punya acceptance criteria; triage zero-tolerance untuk expired/ineligible; CP-SAT tidak menghasilkan hard-constraint violation pada fixture; recommendation advisory dan traceable; serta hipotesis diberi label sebagai hipotesis.

## 8. Sumber utama

Lihat `3_EVALUATION_AND_DOMAIN_RULES/SOURCE_EVALUATION_SUITE_001-030.md` dan `SOURCE_SCHEMA.md`.
