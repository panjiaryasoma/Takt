# Schema Change Request 002

**Request:** SCR-002  
**Status:** DIUSULKAN UNTUK ACCEPTANCE BLOCK 2  
**Menggantikan untuk `Task`:** field effort baseline schema v1.0.0

## Perubahan
Migrasikan kontrak workload canonical `Task` dari floating-point hours menjadi strict integer minutes dan wajibkan asumsi task secara eksplisit.

Field canonical lama:
- `effort_min_hours: float`
- `effort_likely_hours: float`
- `effort_max_hours: float`

Field canonical baru:
- `effort_min_minutes: integer`
- `effort_likely_minutes: integer`
- `effort_max_minutes: integer`
- `assumptions: list[string]`

Invariant effort range tetap wajib:

```text
effort_min_minutes <= effort_likely_minutes <= effort_max_minutes
```

## Alasan
Availability sudah direpresentasikan dalam menit dan solver CP-SAT downstream memakai decision variable integer. Mempertahankan workload canonical sebagai floating-point hours akan memaksa konversi unit berulang dan menambah ambiguitas rounding yang sebenarnya tidak perlu pada boundary scheduling. Karena itu integer minutes menjadi satu-satunya unit workload canonical.

`Task.assumptions` menjadi required supaya estimasi effort tetap dapat ditelusuri ke kondisi yang mendasarinya dan tidak terlihat seperti presisi tanpa dasar.

## Dampak kompatibilitas
Ini adalah breaking wire-contract change untuk `Task`. Payload yang masih memakai `effort_min_hours`, `effort_likely_hours`, atau `effort_max_hours` tidak lagi canonical dan harus dimigrasikan sebelum melewati workload decision boundary. Numeric string, floating-point minute, dan boolean tidak diterima sebagai canonical minute effort.

## Migrasi
Khusus payload historis, adapter migrasi eksplisit boleh mengonversi hours menjadi minutes sebelum validasi. Kontrak workload aktif sendiri tidak menerima dua unit sekaligus dan tidak mempertahankan compatibility alias.

Dokumentasi implementation-facing, shared DTO, fixture, dan test harus memakai field integer-minute setelah SCR ini diterima. Schema historis tetap dipertahankan untuk traceability.

## Identifier versi schema
Identifier aktif `FEATURE_SCHEMA_FINAL.yaml` berubah dari `1.0.0` menjadi `2.0.0` melalui request ini. Identifier sengaja dibuat berbeda karena request ini mengubah nama field required, tipe, dan keanggotaan field required. Keputusan ini hanya menetapkan identifier untuk SCR-002 dan tidak menetapkan kebijakan semantic versioning global untuk perubahan schema berikutnya.
