# Hari 7 Release Audit

Hari 7 is a **release audit**, not a new implementation milestone.

The design and semantics are inherited from the frozen product/domain contracts and the completed implementation through Hari 6. H7 exists to prove the release candidate matches those authorities, record evidence, and issue a GO/HOLD verdict.

## Structure

### Hari 7A — Backend release audit

7A verifies the final backend and correctness-critical pipeline:

```text
source ingestion
→ extraction / OCR
→ reconciliation
→ canonical brief
→ readiness
→ availability / workload
→ solver / feasibility
→ recommendation
→ re-evaluation / stale semantics
→ public API
```

7A does not add features or redesign domain semantics.

### Hari 7B — Mobile + end-to-end release audit

7B verifies the final user-facing and local-persistence path:

```text
Analyze
→ Review
→ Plan
→ Decision Report
→ Accept
→ Saved Plans
→ Schedule
→ restart / recovery
```

7B includes recovery, navigation, persistence, responsive behavior, and final mobile build evidence. It does not redefine backend or domain truth.

## Authority hierarchy

Use the following hierarchy when evidence or prose disagrees:

1. **Executable implementation + tests** for current behavior.
2. **Public error authority:** `tests/support/public_error_matrix.py`.
3. **Recovery authority:** `tests/fixtures/reliability/recovery_policy_v1.json`.
4. **Frozen domain / preproduction contracts:** `docs/05_PREPRODUCTION/01_CONTRACTS_ACTIVE/`.
5. **Implementation evidence:** `docs/evidence/`.
6. Older `*_DRAFT.md`, planning, handoff, and historical material are context only and must not override current authorities.

A documentation claim is not evidence by itself. H7 should always trace important claims back to code, executable tests, CI, or a frozen authority.

## Non-negotiable invariants

H7 must preserve at least these boundaries:

```text
UNKNOWN != INFEASIBLE
FAILURE != MISSING
EMPTY RESULT != FAILURE
NO NATIVE TEXT != CORRUPT PDF

CONFLICT remains CONFLICT
unknown eligibility != failed eligibility
technical failure != domain conclusion

SESSION OUTDATED != SUPERSEDED
trusted stale witness cannot be silently erased

suggestion != commitment
Accept truth exists only after local transaction commit
RevenueCat / entitlement cannot change correctness truth

persistence retry != API retry
client/local failure codes != backend public codes
```

## Audit rule

H7 follows this loop:

```text
audit exact head
→ finding?
    no  → record evidence
    yes → HOLD
          → fix in a scoped change
          → re-run regression
          → re-audit the new exact head
```

A finding does not authorize unrelated cleanup, feature work, semantic expansion, or redesign.

## GO / HOLD gate

A release audit can report **GO** only when:

- P0 / critical crash path: 0 known
- HIGH correctness findings: 0 known
- public contract drift: 0
- recovery-authority drift: 0
- hard domain-invariant violations: 0
- trusted truth loss: 0
- unresolved critical persistence corruption: 0
- required CI jobs: green on the audited head
- known limitations: explicit and non-blocking
- evidence identifies the exact audited commit

Otherwise the result is **HOLD**.

## Evidence outputs

Expected H7 evidence:

```text
docs/evidence/7a-backend-release-audit.md
docs/evidence/7b-mobile-release-audit.md
```

After both audits are GO, a final release-candidate evidence note may be added:

```text
docs/evidence/release-candidate-final.md
```

Do not create that final note before both release audits are complete.

7A execution record: [backend release audit](../evidence/7a-backend-release-audit.md).

7B execution record: [mobile release audit](../evidence/7b-mobile-release-audit.md).

Final release-candidate closure: [release-candidate final evidence](../evidence/release-candidate-final.md).
