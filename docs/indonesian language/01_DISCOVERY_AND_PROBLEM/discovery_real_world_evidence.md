# Evaluasi Discovery — Kasus Dunia Nyata

**Versi:** 1.0  
**Tanggal:** 2026-09-21  
**Tujuan:** menguji apakah problem brief tetap masuk akal ketika berhadapan dengan rules kompetisi nyata, semantik kalender, scheduling technology, document extraction constraints, dan human-AI governance.

## 1. Pertanyaan discovery

Apakah ada masalah nyata yang berulang pada irisan pemahaman rules kompetisi, readiness/eligibility checking, workload decomposition, calendar-aware capacity, feasible work allocation, dan human-controlled recommendation?

## 2. Kasus kompetisi nyata

### Kasus A — Shipaton 2026
Shipaton memiliki deadline dengan Pacific Time, geographic restriction, kondisi Next Gen khusus mahasiswa, jalur submission mahasiswa berbeda, dan category-specific evidence. Informasi tersebar di FAQ, Next Gen, announcement, dan submission guide (`SRC-001`–`SRC-004`).

**Implikasi:** satu URL dapat tidak cukup. Source model harus mendukung beberapa halaman terkait dan mempertahankan asal setiap field.

### Kasus B — Swift Student Challenge 2026
Ada minimum age yang bergantung region, student-status requirement, individual-only work, offline-judged app playground, ZIP size limit, dan exact deadline (`SRC-005`–`SRC-007`).

**Implikasi:** eligibility bersifat conditional, bukan satu boolean dari heading. Requirement juga dapat membatasi arsitektur.

### Kasus C — Imagine Cup 2026
Mensyaratkan enrolled students 18+, team 1–4, penggunaan Microsoft AI service, dan beberapa submission artifact (`SRC-008`).

**Implikasi:** task generation harus membedakan product work dari mandatory submission work. Required technology adalah first-class field.

### Kasus D — HackMIT 2026
Menggabungkan age rule dengan exception untuk mahasiswa MIT dan mendefinisikan student status relatif terhadap event period (`SRC-009`).

**Implikasi:** eligibility membutuhkan predicate dan exception; keyword classifier sederhana tidak cukup.

### Kasus E — GitHub Game Off 2025
Announcement/jam page berisi deadline, GitHub repository expectation, dan itch.io submission. FAQ mengklarifikasi team size, sedangkan organizer update mendokumentasikan missed-deadline exception (`SRC-010`–`SRC-013`).

**Implikasi:** source authority dan freshness penting. Canonical report harus mempertahankan conflict/exception, bukan memilih berdasarkan confidence saja.

### Kasus F — GitLab AI Hackathon di Devpost
Official rules memiliki submission/judging window dalam Eastern Time dan age-of-majority language (`SRC-014`).

**Implikasi:** timezone asli harus dipertahankan; local display dinormalisasi terpisah; age eligibility dapat bergantung yurisdiksi.

## 3. Evidence platform

Devpost organizer guidance menempatkan eligibility, project requirements, submission assets, prizes, winner selection, dan judging criteria sebagai informasi eksplisit (`SRC-015`–`SRC-017`).

**Kesimpulan:** canonical competition report harus memiliki eligibility, deliverables, judging criteria, dan submission requirements sebagai core fields.

## 4. Evidence kalender dan planning

Google Calendar FreeBusy dapat mengembalikan busy interval tanpa event title (`SRC-018`). Recurrence memerlukan rule dan exception (`SRC-019`, `SRC-020`). OR-Tools menunjukkan CP-SAT mampu menangani assignment, capacity, non-overlap, dan precedence (`SRC-021`, `SRC-022`). Riset time management/timetable mendukung pentingnya struktur waktu, tetapi tidak memvalidasi produk ini (`SRC-029`, `SRC-030`).

**Kesimpulan:** gunakan calendar-aware capacity, bukan sekadar total weekly free hours. CP-SAT adalah candidate-allocation engine, bukan autonomous life scheduler.

## 5. Mixed-document discovery

PyMuPDF dapat mengekstrak native text/image secara independen dan menyediakan OCR (`SRC-023`, `SRC-024`). PyMuPDF4LLM mendukung hybrid OCR serta beberapa OCR engine (`SRC-025`, `SRC-026`).

```text
PDF
├── FW1: native/structured extraction → Candidate Extraction Report A
└── FW2: visual/OCR extraction       → Candidate Extraction Report B
A + B → field-level reconciliation → Canonical Competition Report
```

Reconciliation terjadi **setelah** extraction. Conflict tetap conflict sampai diselesaikan oleh evidence/context/human review.

## 6. Human-AI boundary

NIST AI RMF menekankan reliability, transparency, explainability, privacy, dan human oversight (`SRC-027`, `SRC-028`). Produk tidak boleh mengubah probabilistic extraction atau optimization result menjadi unexplained instruction.

Preferred:
- recommended window: Selasa 19:00–21:00;
- alasan: contiguous free block 2 jam, task memblok integration, buffer 5 jam;
- alternative: Rabu 13:00–15:00;
- pengguna dapat accept/edit/ignore.

Bukan: "Kamu harus bekerja Selasa jam 19:00."

## 7. Evaluasi hipotesis

| Hipotesis | Evidence | Keputusan |
|---|---|---|
| Rules memiliki structured planning-critical fields | Kuat | Pertahankan |
| Requirement dapat tersebar/conditional | Kuat | Pertahankan multi-source/provenance |
| Calendar-aware capacity relevan | Sedang-kuat | Pertahankan |
| Deterministic feasibility engine cocok | Kuat secara teknis | Pertahankan |
| Dual-path PDF extraction membantu mixed document | Rasional teknis kuat; product accuracy belum diuji | Pertahankan + evaluasi |
| User membutuhkan final auto-generated timeline | Lemah/bertentangan dengan decision support | Tolak |
| User membutuhkan recommendation + alternatives + trade-offs | Plausible, belum behaviorally validated | Hipotesis MVP |
| Social teammate matching dibutuhkan | Belum terbukti | Exclude |
| Custom ML wajib saat launch | Tidak | Tolak untuk MVP |
| Monetization willingness sudah terbukti | Tidak | Validasi terpisah |

## 8. Keputusan discovery

**GO, dengan framing dipersempit.**

Lanjutkan sebagai **calendar-aware competition decision-support system**. Jangan posisikan sebagai autonomous agent, AI project manager, social network, atau final-schedule generator.

> Ubah sumber kompetisi yang berantakan menjadi canonical brief dengan provenance; evaluasi terhadap calendar constraints nyata; hasilkan feasible work options; jelaskan recommendation/trade-off; pertahankan human decision authority.

## 9. Sumber discovery

Daftar sumber resmi dan teknis tetap menggunakan judul asli agar mudah diverifikasi:

- `SRC-001` Shipaton 2026 FAQ — https://www.shipaton.com/faq
- `SRC-002` Shipaton 2026 Next Gen Award — https://www.shipaton.com/next-gen
- `SRC-003` Shipaton submission guide — https://www.shipaton.com/blog/how-to-submit-your-app-for-shipaton
- `SRC-004` Shipaton announcement — https://www.shipaton.com/blog/announcing-shipaton-2026
- `SRC-005` Swift Student Challenge Eligibility — https://developer.apple.com/swift-student-challenge/eligibility/
- `SRC-006` Swift Student Challenge Terms — https://developer.apple.com/swift-student-challenge/policy/
- `SRC-007` Swift Student Challenge Apply — https://developer.apple.com/swift-student-challenge/apply/
- `SRC-008` Imagine Cup FAQ — https://imaginecup.microsoft.com/en-us/support/faq
- `SRC-009` HackMIT FAQ — https://hackmit.org/?lang=en
- `SRC-010` GitHub Game Off announcement — https://github.blog/company/github-game-off-2025-theme-announcement/
- `SRC-011` GitHub Game Off itch.io — https://itch.io/jam/game-off-2025
- `SRC-012` GitHub Game Off FAQ — https://itch.io/jam/game-off-2025/topic/5489423/frequently-asked-questions-faq
- `SRC-013` Game Off missed-deadline notice — https://itch.io/jam/game-off-2025/topic/5604242/if-you-miss-the-submission-deadline
- `SRC-014` GitLab AI Hackathon Rules — https://gitlab.devpost.com/rules
- `SRC-015` Devpost eligibility docs — https://help.devpost.com/article/143-setting-eligibility-requirements
- `SRC-016` Devpost rules docs — https://help.devpost.com/article/140-creating-hackathon-rules
- `SRC-017` Devpost judging docs — https://help.devpost.com/article/64-judging-public-voting
- `SRC-018` Google Calendar FreeBusy — https://developers.google.com/workspace/calendar/api/v3/reference/freebusy/query
- `SRC-019` Google Calendar Events — https://developers.google.com/workspace/calendar/api/v3/reference/events
- `SRC-020` RFC 5545 iCalendar — https://www.rfc-editor.org/info/rfc5545/
- `SRC-021` OR-Tools Employee Scheduling — https://developers.google.com/optimization/scheduling/employee_scheduling
- `SRC-022` OR-Tools Job Shop Scheduling — https://developers.google.com/optimization/scheduling/job_shop
- `SRC-023` PyMuPDF Basics — https://pymupdf.readthedocs.io/en/latest/the-basics.html
- `SRC-024` PyMuPDF OCR Recipe — https://pymupdf.readthedocs.io/en/latest/recipes-ocr.html
- `SRC-025` PyMuPDF4LLM — https://pymupdf.readthedocs.io/en/latest/pymupdf4llm/
- `SRC-026` PyMuPDF4LLM OCR Plugins — https://pymupdf.readthedocs.io/en/latest/pymupdf4llm/ocr-plugins.html
- `SRC-027` NIST AI RMF — https://www.nist.gov/itl/ai-risk-management-framework
- `SRC-028` NIST AIRC Explainability — https://airc.nist.gov/airmf-resources/airmf/3-sec-characteristics/
- `SRC-029` Time-management meta-analysis — https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2026.1700298/full
- `SRC-030` Timetable/attendance research — https://www.sciencedirect.com/science/article/pii/S0014292126002011
