# Schema Change Request 004

**Request:** SCR-004  
**Status:** APPROVED FOR ISSUE 3A COMPLETION  
**Dampak wire schema:** tidak ada  
**Identifier schema aktif:** tetap `3.0.0`

## Perubahan

Bekukan kebijakan deterministik untuk candidate diversity dan recommendation ranking
yang dipakai Issue 3A.

Candidate generation boleh mengembalikan maksimal tiga candidate recommendable dari
boundary solver yang sama. Alternative harus berasal dari CP-SAT solve baru dengan
material-difference constraint; alternative tidak boleh dibuat hanya dengan menggeser
timestamp solution sebelumnya.

Sebuah candidate dianggap materially different dari candidate sebelumnya jika minimal
satu kondisi berikut terpenuhi:

1. memakai set solver availability window yang berbeda; atau
2. waktu completion berbeda minimal 30 menit.

Ranking candidate bersifat deterministik dan hanya dilakukan setelah candidate dengan
hard constraint violation dikeluarkan. Urutan ranking:

1. jumlah work block lebih sedikit;
2. completion lebih awal;
3. canonical schedule signature;
4. deterministic candidate identifier hanya sebagai final stability tie-breaker
   setelah schedule duplikat secara semantik dibuang.

Recommendation alternative hanya dikeluarkan untuk candidate feasible yang materially
different. `CHOOSE_ALTERNATIVE` hanya tersedia jika minimal satu alternative tersebut
ada.

## Alasan

Baseline aktif sudah mewajibkan `CandidateAllocation[]` dan recommendation untuk
menampilkan alternative feasible yang materially different. Satu candidate lalu
menggeser timestamp sedikit tidak memenuhi perilaku itu karena bisa melewatkan plan
valid pada availability window lain sekaligus menampilkan near-duplicate sebagai
alternative.

Ranking policy juga mengubah recommendation semantics sehingga harus versioned dan
tidak boleh hanya hidup di implementation code.

## Dampak kompatibilitas

Tidak ada perubahan field DTO, enum, atau wire type bersama.
`FEATURE_SCHEMA_FINAL.yaml` tetap pada schema version `3.0.0`.

Perubahan hanya pada behavior:

- candidate enumeration mencari plan feasible yang materially distinct;
- shift kecil di bawah 30 menit pada window yang sama bukan alternative;
- ranking semantics dibekukan oleh request ini;
- human-commit boundary tidak berubah.

## Acceptance

- setiap candidate yang direkomendasikan punya zero hard-constraint violations;
- availability window feasible yang terpisah dapat menghasilkan candidate berbeda;
- schedule pada window yang sama yang hanya berbeda kurang dari 30 menit bukan
  alternative;
- ranking deterministik untuk semantic input yang sama;
- recommendation alternative dapat dilacak ke candidate solver nyata;
- tidak ada candidate atau alternative yang otomatis di-commit ke kalender.
