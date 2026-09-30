# H-6B canonical audit — final

Status: **CLOSED / MERGED**.

Hari 6B was audited after Hari 6A landed on `main`, remediated on PR #34, verified on the exact PR head, and then merged.

## Final identities

- Hari 6A merge on `main`: `34eae0de10316ae85666a422a767ea12d429d7d6`
- Hari 6B final PR head: `71fc10cd6823ee62cdffe5efa951f828c419b702`
- Hari 6B merge commit: `4c3bfe3e5ef800f17dc8ab35f809aa59e4fdd215`
- PR: #34
- Exact-head CI: run #267 — **SUCCESS**

## Recovery authority

`tests/fixtures/reliability/recovery_policy_v1.json` owns recovery classes.

`tests/support/public_error_matrix.py` owns public endpoint/code/status/stage contracts.

Flutter parity is checked by `apps/mobile/test/recovery_policy_parity_test.dart`, which consumes the joined Python export at test time. There is no checked-in Flutter copy of the public error catalog. Unknown backend codes fail closed.

`NO_AUTOMATIC_RECOVERY` and `RELOAD_CONTEXT` block ordinary Evaluate/Re-evaluate paths. Recovery behavior is derived from `RecoveryClass`; compatibility `retryable` projections are not an authority.

Client transport and local failures remain separate namespaces from backend public codes.

## Durable truth and recovery

| State | Recovery | Can discard? |
| --- | --- | --- |
| Fresh analysis/evaluation result not committed | Retry local save using captured material | Explicit confirmation only |
| Trusted re-evaluation transition not persisted | Retry local save | No |
| Evaluation/transition committed, publication/readback failed | Retry reload/read | No |
| Accept confirmed, transaction failed | Retry acceptance save or cancel pending intent | Explicit cancellation; accepted truth does not yet exist |
| Accept committed, projection refresh failed | Keep accepted truth; refresh projections | No |
| Task progress committed, refresh failed | Keep durable progress; retry refresh | No write replay |

System Back cannot silently erase unresolved Analysis persistence. Explicit discard remains the only destructive exit for discardable unsaved results.

Trusted `SUPERSEDED` state is correctness-bearing and non-discardable once established in the lifecycle.

Accepted truth exists only after the local transaction commits. A post-commit projection failure cannot reclassify the Accept operation as failed.

## Regression evidence

The final remediation closes the canonical post-6A audit findings:

| Area | Final status |
| --- | --- |
| Cross-language recovery-policy parity | PASS |
| Unknown-code fail-closed behavior | PASS |
| Analysis system-Back persistence safety | PASS |
| Planning recovery-action gating | PASS |
| Request retry vs persistence retry separation | PASS |
| Trusted stale witness preservation | PASS |
| Pending Accept retry/cancel semantics | PASS |
| Commit vs publication/readback boundary | PASS |
| Saved Plan local-read recovery | PASS |
| Local error-message sanitation | PASS |
| Drift transaction / FK integrity | PASS |
| Fresh DB / v1→v3 / v2→v3 migration | PASS |
| Restart persistence | PASS |
| Recovery surfaces at 320px / 2x text | PASS |

## Exact-head verification

CI run #267 on `71fc10cd6823ee62cdffe5efa951f828c419b702`:

- Python Ruff: PASS
- Python tests: **924 passed, 4 warnings**
- Flutter analyze: PASS
- Flutter tests: **286 passed**
- Android debug build: PASS
- iOS debug build without signing: PASS

The merge commit itself is the implementation baseline for pre-H7 documentation. H7 must still verify the exact release-candidate head rather than treating this evidence as a permanent substitute for release audit.

## Known evidence boundaries

Automated widget evidence at 320px / 2x does not claim arbitrary device coverage.

The suite does not claim arbitrary OS process-death recovery for in-memory unsaved responses.

Real external network outages remain environment-dependent; client transport failure behavior is covered with controlled tests.

No backend runtime, solver, domain semantic, public wire, or entitlement-correctness mutation belongs to Hari 6B.
