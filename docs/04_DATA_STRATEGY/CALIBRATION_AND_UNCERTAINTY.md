# Calibration and Uncertainty

**Version:** 1.0

The product deals with source uncertainty, effort uncertainty, constraint uncertainty and recommendation uncertainty. False precision is harmful because users may change real schedules based on the output.

## Source uncertainty
Represent with canonical field state, provenance, conflict and missingness. Extractor confidence does not override conflicting authoritative evidence.

## Effort uncertainty
MVP uses minimum / likely / maximum. Future models may use quantile or conformal intervals if justified by real data.

## Constraint uncertainty
Expose assumptions, fixed/flexible semantics, buffer sensitivity and availability changes.

## Recommendation uncertainty
Expose rationale, trade-offs and alternatives. Avoid unsupported probability language.

## Feasibility sensitivity
Prefer statements such as:
```text
Likely workload: 31–38h
Available capacity: 42h
Buffer: 4–11h
If backend work overruns by 4h, status becomes TIGHT_CAPACITY.
```
over fabricated "87% feasible" scores.

## Probability gate
Before user-facing probabilities: define empirical target, measure held-out calibration, review reliability diagram/equivalent, report Brier/log-loss where appropriate, and recheck after distribution shift.

## Abstention
Abstain when critical conflicts, missing eligibility attributes, incomplete calendar horizon, incomplete mandatory deliverables, or unsupported domains prevent a defensible result.
