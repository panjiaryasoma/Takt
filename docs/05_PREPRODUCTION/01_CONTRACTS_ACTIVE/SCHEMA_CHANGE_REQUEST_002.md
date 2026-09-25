# Schema Change Request 002

**Request:** SCR-002  
**Status:** PROPOSED FOR BLOCK 2 ACCEPTANCE  
**Supersedes for `Task`:** baseline schema v1.0.0 task effort fields

## Change
Migrate the canonical `Task` workload contract from floating-point hours to strict integer minutes and require explicit task assumptions.

Old canonical fields:
- `effort_min_hours: float`
- `effort_likely_hours: float`
- `effort_max_hours: float`

New canonical fields:
- `effort_min_minutes: integer`
- `effort_likely_minutes: integer`
- `effort_max_minutes: integer`
- `assumptions: list[string]`

The effort range invariant remains mandatory:

```text
effort_min_minutes <= effort_likely_minutes <= effort_max_minutes
```

## Why
Availability is already represented in minutes and the downstream CP-SAT solver uses integer decision variables. Keeping canonical workload effort as floating-point hours would force repeated unit conversion and introduce avoidable rounding ambiguity at the scheduling boundary. Integer minutes therefore become the single canonical workload unit.

`Task.assumptions` becomes required so effort estimates remain traceable to the conditions under which they were produced instead of appearing as unsupported precision.

## Compatibility impact
This is a breaking wire-contract change for `Task`. Payloads using `effort_min_hours`, `effort_likely_hours`, or `effort_max_hours` are no longer canonical and must be migrated before crossing the workload decision boundary. Numeric strings, floating-point minute values, and boolean values are not accepted as canonical minute effort.

## Migration
For historical payloads only, an explicit migration adapter may convert hours to minutes before validation. The active workload contract itself does not accept both units and does not retain compatibility aliases.

Implementation-facing documentation, shared DTOs, fixtures, and tests must use integer-minute fields after this SCR is accepted. Historical schema files remain unchanged for traceability.

## Schema version identifier
The active `FEATURE_SCHEMA_FINAL.yaml` identifier changes from `1.0.0` to `2.0.0` with this request. The identifier is intentionally distinct because this request changes required field names, types, and required membership. This decision establishes the identifier for SCR-002 only; it does not define a repository-wide semantic-versioning policy for future schema changes.
