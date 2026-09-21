# Aturan Data Leakage

**Version:** 1.0

Leakage terjadi ketika evaluasi memakai informasi yang belum tersedia saat prediction atau entity terkait bocor antar split sehingga evaluasi terlihat lebih mudah daripada kenyataannya.

## Temporal leakage
Forbidden: actual effort before task execution; final completion status for initial feasibility; post-deadline rule updates in an earlier historical snapshot; future calendar changes in an earlier recommendation.

## Target leakage
Forbidden: risk score used to generate a feasibility label and then used to predict that label; overrun ratio used to predict actual effort; synthetic acceptance probability used to predict acceptance.

## Entity leakage
For unseen-user effort evaluation, group by `user_id`. Personalized known-user evaluation may use a chronological split and must be reported separately.

## Competition/document leakage
Near-duplicate pages/renders of the same competition or PDF remain in the same split group. Native, OCR, rasterized and perturbed versions of one source family must not leak across train/test.

## Synthetic-generator leakage
A model can learn generator equations. Synthetic scores are engineering metrics, not external validity.

## Primary split keys
| Task | Split key |
|---|---|
| effort, unseen users | user_id |
| effort personalization | time within user |
| source extraction | source_family_id / competition_id |
| OCR robustness | original_document_id |
| user study | participant_id |
| solver fixtures | fixture family |

## Benchmark gate
List target, feature availability, label-derived variables, group integrity and duplicate/source-family isolation before any benchmark is accepted.
