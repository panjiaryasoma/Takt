# Strategi Dataset

**Versi:** 1.0  
**Status:** spesifikasi pre-production

## Prinsip
Kebijakan data harus dibuat sebelum training-data freeze. Kita tidak membuat dataset yang nyaman dulu, mendapat score cantik, lalu menulis metodologi untuk membenarkannya.

## Kelas data
1. **Real public source corpus** untuk extraction, canonical-field validation, provenance, dan conflict evaluation.
2. **Synthetic deterministic/adversarial fixtures** untuk calendar constraints, recurrence, CP-SAT invariant, reconciliation, dan edge case.
3. **Real behavioral/outcome data** untuk learned effort estimation, calibration, recommendation usefulness, dan completion behavior.

## Dataset family
- DS-01 Source Understanding Corpus
- DS-02 Calendar Constraint Fixtures
- DS-03 Solver Feasibility Fixtures
- DS-04 Task Effort Dataset
- DS-05 Recommendation Evaluation Dataset

## Keputusan MVP
Gunakan pretrained LLM/OCR + deterministic reconciliation, rules untuk readiness, CP-SAT untuk feasibility, heuristic transparan untuk recommendation, dan effort range yang bisa diedit user. Custom-trained ML tidak wajib.

## Status synthetic pack
```text
EXPERIMENTAL
NOT SOURCE OF TRUTH
NOT FINAL TRAINING DATASET
NOT PRODUCT EVIDENCE
```
