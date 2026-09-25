# Schema Change Request 003

**Request:** SCR-003  
**Status:** PROPOSED FOR BLOCK 3 ACCEPTANCE  
**Menggantikan untuk `CandidateAllocation`:** field candidate allocation schema v2.0.0

## Perubahan
Migrasikan candidate allocation solver ke unit waktu canonical integer minutes yang sama dengan availability dan workload, lalu ganti work block bertipe bebas menjadi allocation block eksplisit.

Field canonical lama:
- `buffer_hours: float`

Field canonical baru:
- `buffer_minutes: integer`

Contract `AllocationBlock` baru:
- `task_id`
- `start`
- `end`
- `allocated_minutes`
- `availability_source`

`CandidateAllocation.work_blocks` menjadi list `AllocationBlock` bertipe eksplisit. `hard_constraint_violations` dan `assumptions` tetap menjadi field candidate yang wajib hadir.

## Alasan
Capacity Block 1 dan effort Block 2 sudah memakai integer minutes, sedangkan decision variable CP-SAT juga integer-based. Mempertahankan buffer candidate sebagai floating-point hours akan mengembalikan ambiguity unit tepat setelah migrasi workload. Allocation block bertipe eksplisit juga diperlukan untuk post-solver invariant check terhadap availability containment, duration, dependency order, deadline, dan daily capacity.

## Dampak kompatibilitas
Ini breaking wire-contract change untuk `CandidateAllocation`. Payload dengan `buffer_hours` tidak lagi canonical. `work_blocks` bertipe bebas juga tidak lagi diterima di candidate boundary.

## Migrasi
Candidate payload historis boleh dikonversi lewat adapter eksplisit sebelum validasi. Contract solver aktif tidak menerima compatibility alias. Fixture dan test implementasi baru memakai `buffer_minutes` dan typed allocation blocks.

## Identifier versi schema
Identifier `FEATURE_SCHEMA_FINAL.yaml` aktif berubah dari `2.0.0` menjadi `3.0.0` melalui request ini. Identifier dibedakan karena request ini mengubah nama dan tipe required field serta struktur solver work block. Keputusan ini hanya menetapkan identifier untuk SCR-003 dan tidak menetapkan kebijakan semantic versioning global repository.
