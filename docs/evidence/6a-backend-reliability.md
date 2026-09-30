# 6A backend reliability evidence

Date: 2026-09-30. Branch: `H-6A`.
Base: `main` at `7986a6fd967f93327b1fcf272095523f90190ad5` (merged 5B).

Implementation and local verification are complete. **The CI completion gate is pending**:
the existing workflow runs on pull requests and pushes to `main`, not pushes to `H-6A`.
No pull request or merge was authorized for this implementation. Do not label 6A fully
closed until CI has passed for the resulting commit/PR.

## Scope and production correction

The sole production change is in `engine/extraction/ocr/service.py`. A provider could
return the final page after the timeout budget and still produce a successful OCR
document: the old code checked the remaining budget only before calling the provider.
The two initial reproductions advanced a fake monotonic clock to 120 and 121 seconds;
both failed with `DID NOT RAISE OCRTimeoutError` before the correction.

The shared OCR boundary now rejects late provider results against both the per-operation
and total deadlines, and checks the total budget again before returning the document.
Regression cases cover 20/21/120/121-second late results, the shrinking final-page budget
(six 19-second pages leave only six seconds for page seven), and a successful empty
result just inside the deadline. The public error remains the existing `OCR_TIMEOUT`.

This check rejects late results; it does not introduce thread/process cancellation for
arbitrary injected providers. The production Tesseract provider already bounds its child
process with `subprocess.run(timeout=...)`. PDF rendering and Python processing remain
synchronous, with budget checks at the existing operation boundaries.

There are no changes to API/contracts, domain semantics, mobile/Drift, dependencies,
deployment, or CI configuration. There is no backend Accept endpoint. Only the proven
OCR bug, tests, a recovery fixture/adapter, and this evidence are added.

## Verification

Commands were run on the implementation tree used for the performance artifact:

```sh
uv run --locked ruff check apps engine packages tests scripts
uv run --locked pytest -q
uv run --locked python -m tests.reliability.test_6a_performance_baseline \
  --output docs/evidence/6a-performance-baseline.json
```

| Gate | Observed result |
| --- | --- |
| Ruff, full Python scope | PASS |
| Full backend pytest | **924 passed**, 2 existing dependency deprecation warnings |
| New 6A reliability suite | **152 passed** |
| 5A public error rows covered by recovery policy | **76 / 76**, no missing or duplicate references |
| Existing contract/wire and backend regression tests | Included in the full pytest result |
| CI on H-6A implementation | PENDING PR authorization/run |
| Flutter-side recovery parity / local persistence | 6B responsibility; not claimed here |

Environment: Linux x86_64, Python 3.12.14, Tesseract 5.3.4. The hosted runner supplies
a SOCKS proxy; three existing network-boundary tests initially failed at httpx client
construction because its optional `socksio` package was absent. Installing `socksio==1.0.0`
in the temporary test environment resolved that runner prerequisite. Project dependencies
and `uv.lock` were unchanged. The recorded 924-pass run includes those three tests.

| Suite | Evidence |
| --- | --- |
| `test_6a_failure_contract.py` | All 5A rows through existing route/error handlers; wire status/code/stage/detail shape and transition; recovery parity; invalid policy rejection; private exception sentinel absent |
| `test_6a_source_adversarial.py` | Schema vs ingestion failures, unsafe URL/DNS, timeout/network/HTTP failures, unreadable PDF, image-only and empty success, independent OCR errors, resource and time budgets |
| `test_6a_domain_solver_failures.py` | Eight exact domain scenarios; dependency cycle before solver; real CP-SAT boundary induced UNKNOWN; solver/availability crashes; blocked/infeasible Accept prohibition |
| `test_6a_stale_determinism.py` | Semantic equality, candidate/task/provenance resolution, independent hard-constraint validation, trusted stale witnesses, corrupted prior context, entitlement header invariance, native/OCR conflict preservation |
| `test_6a_backend_duplicate_work.py` | One retrieval transaction including redirects, identical native/OCR snapshot, UNCHANGED execution suppression, one availability/feasibility stage and one solve per intended scenario |
| `test_6a_performance_baseline.py` | Nine measured stages, real OCR, finite observations, no timing threshold |

All assertions describe the exercised fixtures, not a universal proof of every possible
source or schedule. Solver UNKNOWN is deliberately induced at `CpSolver.Solve`, while
checking the actual configured workers=1, seed=0, deterministic-time budget=10.0. The test
does not wait for a machine-dependent difficult model to exhaust its budget.

Existing streamed-body limit tests remain in `tests/extraction/test_native_ingestion.py`.
The new suite additionally exercises the default 20 MiB upload/declared-response cap,
native PDF 250/251-page boundary, OCR 50/51-page boundary before rendering, owned HTTP
client timeout of 15 seconds, and OCR 20/120-second operation/total budgets. HTTP timeout
is the existing httpx timeout configuration, not a newly introduced whole-request SLO.

Duplicate-work counts respect existing solver semantics: MIN, LIKELY, MAX and
FULL_SCOPE_LIKELY each solve once. Each scenario may intentionally search up to three
materially distinct candidates; successive searches carry prior solutions. Recommendation
uses the same LIKELY candidates without a second feasibility run.

Entitlement checks compare absent/free/pro headers through the current HTTP route. The
backend has no entitlement input to its correctness engine; existing request-contract and
engine-boundary guards also run in the full regression suite. No RevenueCat network call
or new access-control behavior is claimed.

## Recovery policy and 6B handoff

`tests/support/public_error_matrix.py` remains the only authority for HTTP status, public
code, stage, detail shape and transition semantics. It is unchanged.

`tests/fixtures/reliability/recovery_policy_v1.json` is the cross-language recovery SSOT:
57 scenarios, seven recovery classes. Python reads it via `tests/support/recovery_policy.py`.
6B should read the same JSON fixture from the repository root, not copy its mapping into
another fixture. Flutter parity is deliberately not implemented in this backend branch.

For an error scenario, `contract_key` names a 5A `failure_class`; `endpoints` disambiguates
the public boundary and makes coverage checkable. No status/code/stage catalog is copied.
Domain/transition scenarios use `contract_key: null` and one `expected_state`. Scenario IDs
are fixture identities, not new API fields. Unknown scenarios have no optimistic default.

| Recovery class | Meaning for the later presentation layer |
| --- | --- |
| FIX_INPUT | Correct authoritative input/source information; never manufacture a canonical fact |
| RETRY_SAME_INPUT | A retry may be offered after the transient/provider/runtime issue is resolved; success is not guaranteed |
| REUPLOAD_SOURCE | Replace or reupload an unreadable/unsupported source |
| EDIT_CONSTRAINTS | Reconsider planning constraints and evaluate the changed input |
| REEVALUATE | Request a fresh evaluation for the current trusted basis |
| RELOAD_CONTEXT | Reload authoritative report/evaluation context before retrying |
| NO_AUTOMATIC_RECOVERY | Do not invent an automatic repair, retry loop, or domain conclusion |

Recovery labels do not grant ACCEPT or override `allowed_actions`. The trusted transition
is processed independently: a wrapped re-evaluation error may preserve an already proven
SUPERSEDED witness; a failure before that witness has `transition: null`. Recovery cannot
make the old evaluation current again. A successful SUPERSEDED response already contains
the fresh evaluation and must not trigger a gratuitous second evaluation.

Double-submit, double-Accept, exact-session persistence revalidation, input retention,
retry UX, Drift transactions, migrations and restart resilience remain 6B work.

## Observational performance

Raw samples, fixture hashes, dependency versions, measurement-code digest and method are
in [`6a-performance-baseline.json`](6a-performance-baseline.json). Each stage has one warm-up
and five recorded samples. These are small warm fixtures, not production capacity or
Railway latency. E2E means in-process HTTP request validation through response serialization;
outbound source retrieval uses MockTransport and fixed public DNS. OCR runs real Tesseract
against the existing two-page image PDF, with provider initialization outside timing.

| Stage | Median ms | Observed min–max ms |
| --- | ---: | ---: |
| Native HTML | 0.346 | 0.320–0.369 |
| Native PDF | 0.906 | 0.851–0.959 |
| OCR fixture | 454.091 | 441.037–465.956 |
| Reconciliation and canonical assembly | 1.145 | 1.143–1.692 |
| Availability | 0.037 | 0.033–0.047 |
| LIKELY solver candidate pool | 2.093 | 2.076–2.725 |
| Plan evaluate HTTP E2E | 13.663 | 13.228–14.813 |
| Competition analysis HTTP E2E | 3.564 | 3.507–4.451 |
| UNCHANGED re-evaluation HTTP E2E | 4.705 | 4.056–7.325 |

No performance number is a CI threshold. Hard resource/time budgets have separate
deterministic regression checks. Rerun the command to compare environments; do not treat
these local observations as a deployment benchmark or service-level guarantee.
