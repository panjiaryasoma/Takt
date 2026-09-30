# H-6B canonical audit remediation

Scope: the post-6A-sync audit of PR #34 (five HIGH, two MEDIUM, two LOW/evidence findings). Starting head: `01bbde0c058883e54af90a04e394b7ab12058e4d`; synced main: `34eae0de10316ae85666a422a767ea12d429d7d6`.

## Recovery authority

`tests/fixtures/reliability/recovery_policy_v1.json` owns recovery classes. `tests/support/public_error_matrix.py` owns public endpoint/code/status/stage contracts. The Flutter parity test invokes the stdlib-only Python adapter to join these sources at test time and check every public row against Dart. There is no checked-in copy of the public error catalog. Unknown codes fail closed.

`NO_AUTOMATIC_RECOVERY` and `RELOAD_CONTEXT` block ordinary Evaluate and draft mutation in the host, not just in the screen. Reload is an explicit local-context operation. Fix-input/edit-constraints recovery requires a material input edit; changing a local timestamp or resubmitting the same form does not reset the failure. The unsupported-contract fresh-baseline shortcut is removed.

## Durable truth and recovery

| State | Recovery | Can discard? |
| --- | --- | --- |
| Fresh evaluation transaction failed | Retry local save, using the captured response | Explicit confirmation only |
| Trusted re-evaluation transition not persisted | Retry local save | No |
| Evaluation/transition committed, publication failed | Retry reload; reads only | No |
| Accept confirmed, transaction failed | Retry acceptance save or cancel pending intent | Explicit cancellation; no accepted truth yet |
| Accept committed, projection refresh failed | Keep accepted truth; refresh projections | No |
| Task progress committed, refresh failed | Report progress as saved; retry refresh | No save replay |

Analysis Back preserves pending persistence, including when Back is pressed from another root tab. Edit/reset/replacement shortcuts cannot erase the pending result. The existing explicit discard confirmation remains the only discard path.

Saved Plan's asynchronous Re-evaluate preparation is awaited inside a local recovery boundary. A repository read failure retains the accepted detail and presents a reload action without calling the evaluation API. Local read, parse, save, and publication errors use sanitized `LOCAL_*` classifications; server response contract errors remain separate.

## Regression evidence map

| Finding | Regression coverage |
| --- | --- |
| HIGH-1 parity | `recovery_policy_parity_test.dart`: all 76 joined public cases and unknown-code fail-closed behavior |
| HIGH-2 Back | `analysis_2b_test.dart`: VM shortcut guards, actual system Back, explicit keep/discard, Back during retry-save |
| HIGH-3 action gate | `planning_host_4b_test.dart`: blocked codes, unchanged/timestamp-only drafts, semantic edits, explicit reload, unsupported Saved Plan contract |
| HIGH-4 commit/publication | Fresh evaluation initial save and retry-save commit followed by reload failure; DB row remains durable, write/API counts do not increase during reload |
| HIGH-5 Saved Plan read | Actual RootShell Re-evaluate callback with a failing local repository; recovery panel and local retry, no evaluation request |
| MEDIUM-1 sanitation | Analysis continuation read, planning context/assembly/default reads, Saved Plan context/progress errors |
| MEDIUM-2 refresh | SUPERSEDED success/failure and UNCHANGED transitions plus progress refresh/detail failure after commit |
| LOW-2 responsive evidence | Actual Analysis, Planning recovery states (unsaved, publication, request retry, blocked, reload, stale witness), Saved Plan context/progress recovery, pending Accept at 320px and 2x text |
| LOW-1 PR evidence | PR #34 body must identify the current head/base and its CI run, replacing pre-sync evidence |

## Verification gate

These are implementation and regression assertions, not a claim that writing the tests proves them. Full verification requires the CI run for the published PR head: Python Ruff/tests, Flutter analyze/tests, Android debug APK, and iOS debug build without signing. The pre-fix CI #263 is baseline evidence only. Exact tested head, run URL, outcomes, and remaining limitations are recorded in PR #34 after the run completes.

The UI matrix is automated widget evidence at 320px/2x; it does not claim device screenshot review, real network outage testing, or arbitrary OS process-death recovery of in-memory unsaved responses. No merge is performed by this remediation.
