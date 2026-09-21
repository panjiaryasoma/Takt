# Strategi Split

**Version:** 1.0

Tidak ada random split 80/20 yang selalu benar. Split harus sesuai dengan pertanyaan generalisasi.

## Effort estimation
Primary unseen-user evaluation: grouped 70/15/15 split by `user_id`; all tasks from one user remain in one split.

Secondary personalization evaluation: train on earlier tasks and test on later tasks for the same known user; report separately.

## Source extraction
Group by `source_family_id` or `competition_id`. Native text, OCR render and perturbed derivatives of the same page remain in one group.

## Solver/domain-rule fixtures
Use acceptance, adversarial and regression fixtures rather than train/test terminology. They are deterministic software tests.

## Balanced synthetic view
A 25/25/25/25 feasibility view may be generated for classifier engineering. It must be labeled artificial and must never be treated as real prevalence.

## Final real-world test set
Freeze a held-out set, document collection period/population/missingness/exclusions, and do not repeatedly tune on it.

## Reproducibility
Persist split seed, group key, exact IDs, split code/version and data-snapshot hash.
