# Schema Change Request 001

**Request:** SCR-001  
**Status:** APPROVED

## Perubahan
Promosikan feature inventory lama menjadi kontrak implementasi aktif. Pisahkan source verification, readiness, feasibility, recommendation, dan human commitment; wajibkan provenance critical field; gunakan effort range; definisikan `CandidateAllocation` sebagai solver output; wajibkan zero hard violation untuk recommendable candidate; wajibkan explicit human acceptance sebelum commitment; tunda direct calendar integration dan learned historical effort adjustment.

## Alasan
Tanpa interface eksplisit, implementasi dapat mencampur semua state menjadi satu "AI result" yang opaque.

## Migrasi
Schema historis tetap disimpan untuk traceability. Implementasi baru memakai `FEATURE_SCHEMA_FINAL.yaml`. Perubahan semantik berikutnya wajib memakai SCR baru.
