# Schema Change Request 003

**Request:** SCR-003  
**Status:** PROPOSED FOR BLOCK 3 ACCEPTANCE  
**Supersedes for `CandidateAllocation`:** schema v2.0.0 candidate allocation fields

## Change
Migrate solver candidate allocation to the same canonical integer-minute time unit used by availability and workload, and replace untyped work blocks with explicit allocation blocks.

Old canonical field:
- `buffer_hours: float`

New canonical field:
- `buffer_minutes: integer`

New `AllocationBlock` contract:
- `task_id`
- `start`
- `end`
- `allocated_minutes`
- `availability_source`

`CandidateAllocation.work_blocks` becomes a typed list of `AllocationBlock` values. `hard_constraint_violations` and `assumptions` remain explicit candidate fields.

## Why
Block 1 capacity and Block 2 effort already use integer minutes, while CP-SAT decision variables are integer-based. Keeping candidate buffer in floating-point hours would reintroduce a unit boundary immediately after the prior workload migration. Typed allocation blocks are also required for post-solver invariant checks covering availability containment, duration, dependency order, deadline, and daily capacity.

## Compatibility impact
This is a breaking wire-contract change for `CandidateAllocation`. Payloads using `buffer_hours` are no longer canonical. Untyped arbitrary `work_blocks` are no longer accepted at the candidate boundary.

## Migration
Historical candidate payloads may be converted by an explicit adapter before validation. The active solver contract itself does not accept compatibility aliases. New implementation fixtures and tests use `buffer_minutes` and typed allocation blocks.

## Schema version identifier
The active `FEATURE_SCHEMA_FINAL.yaml` identifier changes from `2.0.0` to `3.0.0` with this request. The identifier is intentionally distinct because this request changes a required field name, type, and the structure of solver work blocks. This decision establishes the identifier for SCR-003 only and does not define a repository-wide semantic-versioning policy.
