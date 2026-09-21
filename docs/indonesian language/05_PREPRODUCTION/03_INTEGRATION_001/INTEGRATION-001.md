# INTEGRATION-001

## Tujuan
Validate:
```text
CanonicalCompetitionReport
+ user attributes
+ domain rules
→ ReadinessTriage
→ planning gate
```

Fixture sengaja dimulai setelah source extraction.

## Acceptance
1. schema validation berhasil;
2. triage returns exactly `READY_TO_EVALUATE`;
3. critical evidence references remain present;
4. tidak ada directive terhadap pilihan personal user;
5. planning gate terbuka;
6. result is reproducible for the same rule version.

**Status:** `SPECIFIED / NOT_YET_EXECUTED`
