# Schema Change Request 004

**Request:** SCR-004  
**Status:** APPROVED FOR ISSUE 3A COMPLETION  
**Wire schema impact:** none  
**Active schema identifier:** remains `3.0.0`

## Change

Freeze the deterministic candidate-diversity and recommendation-ranking policy used by
Issue 3A.

Candidate generation may return at most three recommendable candidates from the same
solver invocation boundary. Alternatives must come from fresh CP-SAT solves with
material-difference constraints; they must not be created by mechanically shifting a
previous solution.

A candidate is materially different from an earlier candidate when at least one of
these conditions holds:

1. it uses a different set of solver availability windows; or
2. its completion time differs by at least 30 minutes.

Candidate ranking is deterministic and applies only after candidates with hard
constraint violations are excluded. The ranking order is:

1. fewer work blocks;
2. earlier completion;
3. canonical schedule signature;
4. deterministic candidate identifier only as a final stability tie-breaker after
   semantic duplicate schedules have been removed.

Recommendation alternatives are emitted only for materially different feasible
candidates. `CHOOSE_ALTERNATIVE` is available only when at least one such alternative
exists.

## Why

The active baseline already requires `CandidateAllocation[]` and requires
recommendations to surface materially different feasible alternatives. A single
candidate plus small timestamp shifts does not satisfy that behavior because it can
both miss valid plans in different availability windows and expose near-duplicate
plans as alternatives.

The ranking policy also affects recommendation semantics and therefore must be
versioned instead of living only in implementation code.

## Compatibility impact

No shared DTO field, enum, or wire type changes. `FEATURE_SCHEMA_FINAL.yaml` remains
at schema version `3.0.0`.

Behavior changes only:

- candidate enumeration searches for materially distinct feasible plans;
- near-duplicate sub-30-minute same-window shifts are not alternatives;
- ranking semantics are frozen by this request;
- the human-commit boundary remains unchanged.

## Acceptance

- every recommended candidate has zero hard-constraint violations;
- separated feasible availability windows can produce distinct candidates;
- a same-window schedule that differs by less than 30 minutes alone is not an
  alternative;
- ranking is deterministic for semantically identical input;
- recommendation alternatives are traceable to actual solver candidates;
- no candidate or alternative is automatically committed to the calendar.
