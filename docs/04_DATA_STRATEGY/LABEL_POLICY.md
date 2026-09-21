# Label Policy

**Version:** 1.0

## Label types

### Rule labels
Deterministic domain outputs such as `DEADLINE_PASSED`, `ELIGIBILITY_BLOCKED`, `CONFLICT`, and hard-constraint violations. Suitable for synthetic fixtures.

### Solver labels
Derived from fully specified optimization fixtures, such as candidate exists / no candidate exists under current hard constraints. Suitable for deterministic fixtures.

### Behavioral/outcome labels
Require real observation: actual hours, recommendation usefulness, accepted/edited/ignored recommendation, completion outcome. Synthetic substitutes are pipeline-test data only.

## Feasibility semantics
- `FEASIBLE`: valid allocation with meaningful buffer under current assumptions.
- `FEASIBLE_WITH_TRADEOFFS`: valid allocation requiring material compromise.
- `TIGHT_CAPACITY`: minimal buffer and high sensitivity to estimation error.
- `NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS`: no acceptable allocation under current modeled constraints.

None of these state that the user is incapable or should not participate.

## Actual effort
Unknown actual effort is missing, never zero. Do not infer exact actual effort from calendar-slot duration or a completion checkbox.

## Recommendation labels
Useful/not useful, rationale clear/unclear, suggested window realistic/unrealistic, accepted, accepted after edit, alternative chosen, ignored.

Acceptance is not equivalent to correctness.

## Abstention
`UNKNOWN`, `MISSING`, and `NEEDS_REVIEW` are valid outputs.

## Synthetic labels
Must carry generator version, seed, generating rule/equation, and synthetic flag. Synthetic and real labels must not be silently merged in evaluation reports.
