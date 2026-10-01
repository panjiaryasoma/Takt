# Pre-H7 Release Baseline

This file records the implementation state entering Hari 7. It is a baseline, not a permanent substitute for auditing the exact release-candidate head.

## Implementation baseline

```text
Hari 6A merge
34eae0de10316ae85666a422a767ea12d429d7d6

Hari 6B final PR head
71fc10cd6823ee62cdffe5efa951f828c419b702

Hari 6B merge / implementation baseline
4c3bfe3e5ef800f17dc8ab35f809aa59e4fdd215
```

The H7 documentation-preparation commit may be newer than the implementation baseline above. Documentation-only commits do not change runtime behavior, but H7 must still identify and audit its exact final head.

## Final Hari 6 verification entering H7

PR #34 exact-head CI run #267:

```text
Python Ruff        PASS
Python tests       924 passed, 4 warnings

Flutter analyze    PASS
Flutter tests      286 passed

Android debug      PASS
iOS debug          PASS
```

This verifies the final 6B PR head against the already-merged 6A baseline. H7 must re-check release evidence rather than assuming these counts can never change.

## Active authorities

### Public backend failure contract

`tests/support/public_error_matrix.py`

Owns:

- endpoint failure class
- HTTP status
- public code
- stage
- details shape
- trusted transition semantics

### Cross-language recovery policy

`tests/fixtures/reliability/recovery_policy_v1.json`

Owns recovery classes:

- `FIX_INPUT`
- `RETRY_SAME_INPUT`
- `REUPLOAD_SOURCE`
- `EDIT_CONSTRAINTS`
- `REEVALUATE`
- `RELOAD_CONTEXT`
- `NO_AUTOMATIC_RECOVERY`

Flutter must remain a projection/consumer of this authority, not a second recovery-policy source.

### Frozen implementation-facing domain contracts

`docs/05_PREPRODUCTION/01_CONTRACTS_ACTIVE/`

These remain the implementation-facing source for frozen domain semantics unless executable contracts have intentionally superseded a historical representation.

## Runtime architecture entering H7

### Backend

- FastAPI public API
- Pydantic contracts
- native URL/PDF extraction
- OCR fallback
- source reconciliation and canonical provenance
- readiness/domain rules
- availability/workload planning
- OR-Tools CP-SAT scheduling
- feasibility/recommendation assembly
- trusted re-evaluation transitions

### Mobile

- Flutter client
- typed transport / backend / local failures
- recovery projection via `RecoveryClass`
- Analysis operation identity and late-response rejection
- request retry separated from local persistence retry
- Drift/SQLite schema v3
- atomic Accept persistence
- Saved Plan revisions and accepted commitments
- restart/migration recovery
- RevenueCat as access/presentation boundary only

## Frozen correctness boundaries

```text
UNKNOWN != INFEASIBLE
FAILURE != MISSING
EMPTY RESULT != FAILURE
CONFLICT remains CONFLICT

backend recovery authority != Flutter presentation
client/local codes != backend public codes

SUPERSEDED requires trusted evidence
SESSION OUTDATED != SUPERSEDED

recommendation candidate references must resolve
candidate hard violations = 0
accepted blocks must resolve to persisted task/availability provenance

suggestion != accepted commitment
accepted truth exists only after transaction commit

RevenueCat entitlement must not alter:
- canonical facts
- readiness
- feasibility
- candidate validity
- recommendation correctness
```

## Known non-blocking evidence limits entering H7

- OCR timeout enforcement prevents late success and bounds the Tesseract subprocess, but not every synchronous PDF/Python operation is forcibly process-killed at an exact wall-clock instant.
- 320px / 2x coverage is automated widget evidence, not exhaustive physical-device coverage.
- In-memory unsaved responses are not claimed to survive arbitrary OS process death.
- Observational performance evidence is a baseline, not a hard product SLO unless H7 explicitly establishes one.

These limitations must not be silently upgraded into stronger release claims.

## H7 starting rule

7A and 7B must audit the **exact current release-candidate head**.

If H7 finds a blocker:

```text
HOLD
→ scoped fix
→ regression
→ exact-head re-audit
```

Do not mutate frozen semantics merely to make an audit pass.
