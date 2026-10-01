# 7A backend release audit

Date: 2026-10-01 (Asia/Jakarta). Scope: Issue #13. Branch: `H-7A`.
Starting main: `83b15ba31614fd799f1ad9f100a69d2b6c93b3f8`.

**Technical verdict: GO for Hari 7A backend correctness.**
The final runtime implementation audited here is `650d17ff8dabed273ab50ef5d60581697b777367`.
Its exact-head Python gate passes Ruff and **1010 backend tests, zero skipped**, with the
backend evidence bundle uploaded by CI. Three P1/HIGH source-truth findings were found during
7A and all three are fixed with executable regressions. Known P0 = 0 and known HIGH = 0.
The documentation-final PR head must still receive its own green CI; the PR body records that
final publication head/run without changing backend runtime semantics. This is a backend
repository audit, not a production deployment or whole-product release approval. 7B and final
end-to-end/visual release evidence remain separate gates.

## Findings and disposition

Severity: P0 means critical crash/data-loss or unsafe release blocker; P1/HIGH means
incorrect domain facts or a violated authority boundary; P2 means non-blocking maintenance
or documentation work. A known HIGH remains a HOLD even when P0 is zero.

| Finding | Severity | Reproduction and correction | Status |
| --- | --- | --- | --- |
| Repeated conflicting facts in one source/path silently selected the first/last observation | P1 / HIGH | Two supported submission deadlines produced `SINGLE_SOURCE` with one evidence reference. The same defect affected team-size ranges. Scan every explicit label, including multiple labels in one block; reject disagreement through existing `CandidateNormalizationError`. Equal values, including equivalent timezone instants, still yield one resolvable candidate. A supported value beside an unparseable repetition also fails closed in either order. | Fixed; native/OCR regressions cover disagreement, agreement and supported/unsupported repetition |
| Timezone tokens were accepted by prefix | P1 / HIGH | `UTC+07:00`, `GMT+7`, `UTC +07:00`, and `WIBB` became UTC/GMT/WIB facts. Require a complete supported timezone token; unsupported values stay unextracted instead of acquiring a guessed instant. | Fixed; native/OCR regressions retain the unsupported value as unextracted |
| Multiple alternatives inside one explicit label could still authorize the first supported prefix | P1 / HIGH | A single label such as `Submission deadline: Sep 30 ... or Oct 1 ...` or `Team size: 1 to 4; 2 to 6` could publish only the first value. The bounded parser now anchors the first value, detects additional supported values in the same label, rejects disagreement and mixed supported/unsupported alternatives, rejects an unsupported explicit time instead of downgrading to date-only, and still collapses semantically equivalent instants. | Fixed; 34 additional native/OCR regressions cover `or`, slash, semicolon, `and`, invalid trailing values, equivalent instants and unsupported prefixes |
| CI logs did not persist a backend evidence bundle tied to the checked-out commit | P2 / evidence | Python CI checks out the actual PR head, records commit/tree/authority hashes and dependency/OCR versions, and uploads Ruff, pytest log and JUnit XML. Bash pipefail keeps a failed command from becoming a successful `tee` result. | Implemented and exercised by exact-head CI |

Production correction is confined to `engine/extraction/candidate_normalizer.py`.
Its version advances from `rule-based-v1` to `rule-based-v2`, so evidence/extractor
fingerprints identify the changed parser. Public error codes, HTTP statuses, recovery classes,
domain schema, solver/ranking policy, database, mobile and dependencies are unchanged.

The current candidate-report contract permits one field per source/path. It cannot carry
two contradictory observations of that field. The safe bounded correction is to return
the existing normalization failure without publishing a partial canonical report.
This does **not** claim a new intra-source conflict-review feature. Cross-source and
native-versus-OCR conflicts continue to be represented as `CONFLICT` by reconciliation.
`CANDIDATE_NORMALIZATION_FAILED` retains `NO_AUTOMATIC_RECOVERY` under the existing SSOT.

## Verification and reproducibility

Install Python 3.12, `uv`, and the Tesseract CLI with English language data. On the Ubuntu
CI image the OCR package is installed with `apt-get install -y tesseract-ocr`.
From a fresh clone checked out at the audited commit:

```sh
uv sync --locked --dev
tesseract --version
tesseract --list-langs
uv run --locked python scripts/validate_repo.py
uv run --locked ruff check apps engine packages tests scripts
mkdir -p tmp/backend-audit
uv run --locked pytest -q --junitxml=tmp/backend-audit/pytest.xml
```

| Gate | Evidence at this publication stage |
| --- | --- |
| Fresh remote clone / locked setup at starting main | PASS; new `.venv`, 41 packages installed from `uv.lock` |
| Corrected tree / repository validator | PASS |
| Corrected tree / full Python Ruff | PASS |
| Final runtime head / full backend pytest | 1010 passed, 0 failed, 0 skipped; 4 dependency deprecation warnings |
| Normalizer regression coverage | Repeated labels plus 34 added single-label/trailing-value cases across native and OCR; ambiguity fails closed while equivalent instants remain usable |
| Public failure authority / recovery coverage | 76 public rows, 57 recovery scenarios; no missing/duplicate/orphan mapping |
| Exact runtime-head backend CI | PASS; artifact `backend-audit-650d17ff8dabed273ab50ef5d60581697b777367` |
| Documentation-final PR-head CI | PASS; the exact publication head, CI run, and all job conclusions are recorded in PR #36 body so documentation-only commits do not create a self-staling evidence loop |

The hosted local runner supplies a SOCKS proxy without httpx's optional `socksio`.
The first baseline run was **921 passed / 3 failed** during HTTP-client construction,
before the three DNS-guard tests could execute. Setting uppercase `NO_PROXY` alone did
not correct this runner setup. The successful local run clears upper/lowercase proxy
variables **only in the pytest subprocess**:

```sh
uv run --locked env -u ALL_PROXY -u all_proxy -u HTTP_PROXY -u http_proxy \
  -u HTTPS_PROXY -u https_proxy python -m pytest -q
```

These tests mock retrieval/DNS; no live-source success is claimed by that workaround.
No package was added and no application network guard was disabled. Clean GitHub runners
use the ordinary locked pytest command. The remaining local warnings concern FastAPI/
Starlette's test-client deprecations; they are not suppressed and do not justify a dependency
upgrade during the freeze.

## Claims mapped to executable evidence

Paths below are relative to the repository root. All listed tests run in the full backend gate.

| Backend claim | Implementation / test evidence | Boundary of the claim |
| --- | --- | --- |
| URL ingestion, redirect/media/size guards | `engine/extraction/native.py`, `url_security.py`; `tests/extraction/test_native_ingestion.py`, `test_url_security.py`; `tests/reliability/test_6a_source_adversarial.py` | Mocked public HTTP/DNS; ordinary HTML/PDF, not live arbitrary websites or browser rendering |
| Native PDF and OCR operate on the same bytes | `engine/extraction/snapshot_pipeline.py`; `tests/extraction/test_source_snapshot.py`, `test_ocr.py` | Real PyMuPDF and Tesseract fixture tests; PDF paths are independent, not an assertion of OCR accuracy on all documents |
| Reconciliation preserves conflict and provenance | `engine/reconciliation/field_reconciler.py`, `service.py`; `tests/reconciliation/`; `test_native_ocr_disagreement_stays_conflict_with_resolvable_evidence` in `tests/reliability/test_6a_stale_determinism.py` | Confidence alone cannot resolve a critical conflict; agreeing native/OCR from one source do not create independent-source verification |
| Readiness stays separate from feasibility | `engine/triage/service.py`, `engine/integration/competition_analysis.py`; `tests/triage/`, `tests/reliability/test_6a_domain_solver_failures.py` | Blocked readiness has null planning and null planning basis; unknown eligibility is not failed eligibility |
| Calendar capacity preserves timezone/recurrence constraints | `engine/availability/`; `tests/availability/` | Supplied authoritative intervals/commitments; no external calendar authorization or writes |
| Workload ranges and dependency closure are consistent | `engine/workload/`; `tests/workload/` | Validates supplied task models; no general automatic task-decomposition claim |
| Real CP-SAT candidates satisfy hard constraints | `engine/scheduler/`; `tests/solver/`; independent candidate validation in `tests/reliability/test_6a_stale_determinism.py` | At most three materially distinct candidates, deterministic configured search; not guaranteed globally optimal under every budget |
| Feasibility follows the four frozen scenarios | `engine/feasibility/`; `tests/feasibility/`, `tests/reliability/test_6a_domain_solver_failures.py` | `UNKNOWN` on the active classification branch is indeterminate, not infeasible |
| Recommendation is traceable and advisory | `engine/recommendation/`, `apps/api/contracts.py`; `tests/recommendation/`, `tests/api/test_plan_evaluate_behavior.py`, `tests/integration/test_issue4_backend_regression.py` | Candidate/evaluation/report/planning references resolve; no backend Accept or calendar-write endpoint |
| Re-evaluation preserves trusted stale evidence | `apps/api/services/reevaluation.py`; `tests/api/test_plan_evaluate_behavior.py`, `tests/reliability/test_6a_stale_determinism.py` | UNCHANGED suppresses solver execution; SUPERSEDED requires trusted comparison and survives downstream failure |
| RevenueCat cannot change correctness | `tests/api/test_entitlement_correctness_boundary.py`; seven absent/free/pro scenarios in `tests/reliability/test_6a_stale_determinism.py` | No entitlement authority in backend inputs/engines; not a RevenueCat purchase/restore integration test |
| Public failures and recovery remain stable | `tests/support/public_error_matrix.py`, `tests/fixtures/reliability/recovery_policy_v1.json`; `tests/reliability/test_6a_failure_contract.py` | Existing status/code/stage/details and trusted transition semantics; raw private exceptions do not enter the response |

The final runtime exact-head JUnit reports **1010 passed, 0 failed, 0 skipped**.
The additional 34 cases are extraction-normalizer regressions for ambiguity inside one labeled
fact. Existing API, availability, contracts, feasibility, integration, recommendation,
reconciliation, reliability, solver, triage and workload suites remain part of the same full gate.

## Source and planning examples

[`7a-backend-samples.json`](7a-backend-samples.json) records executions of existing synthetic
fixtures against this implementation. It includes:

- a real native PDF parse plus an injected contradictory OCR provider: deadline remains
  `CONFLICT`, selected value is null, and both evidence references resolve;
- a validated report/task/calendar fixture evaluated by real CP-SAT: two candidates,
  independently checked zero hard violations, buffer, allocations, recommendation rationale
  and complete basis trace;
- blocked readiness with no planning, explicit infeasible with only EDIT_CONSTRAINTS/IGNORE,
  and a changed planning basis with a trusted SUPERSEDED transition.

Execution recipes reuse `tests.reliability.support.plan_request`, `domain_request`, `clock`,
`pdf_metadata`; `tests.api.test_competition_analysis_behavior._pdf_bytes` and
`_StaticOCRProvider`; and `tests.api.test_plan_evaluate_behavior._prior_request`.
Run `evaluate_plan(..., clock=clock)` / `reevaluate_plan(..., clock=clock)` for planning,
and `analyze_pdf(..., ocr_provider=_StaticOCRProvider(...))` for the conflict example.
Ingestion timestamps/byte-derived evidence identities may differ on a rerun; assert semantic
state and reference resolution as the regression tests do. The fixed evaluation clock is
fixture context, not the release date. Live URL accuracy and a production LLM are not implied.

## Architecture / contract audit

The attached preproduction baseline and the repository PRD agree on the material boundaries:
source evidence precedes canonical truth; deterministic readiness and scheduling own
correctness; human acceptance owns commitment; entitlement is outside correctness.
The active schema is `3.0.0`, integer minutes with typed allocation blocks; SCR-004 freezes
candidate diversity and ranking. Historical SCR-002/003 proposal headings do not override
the implemented schema, DTOs and regression tests. No new semantic contract is introduced here.

Backend imports and locked dependencies contain no PostgreSQL/ORM persistence stack or
custom-trained ML stack. FastAPI routes call computation services; only the mobile host owns
accepted plans and SQLite persistence. OCR's temporary files are not an accepted-plan database.
Basis fingerprints check material consistency; they are not signatures authenticating an
external publisher. Callers still own exact request/response pairing and authoritative inputs.

The added diagrams in `docs/Architecture/` are retained. `full-architecture.png` and
`e2e-diagram.png` illustrate the current boundary; they are conceptual navigation aids,
not an exhaustive route or execution specification. In particular, PDF analysis runs native
and OCR independently; a diagram's conditional OCR wording must not imply native text can
silently suppress the PDF OCR path. The legacy readiness route is also present in code.
The concrete authorities remain the hierarchy in `docs/07_RELEASE_AUDIT/README.md`.

## Known limitations / frozen claim boundary

- The production normalizer supports explicit English submission-deadline and team-size
  labels only, with a bounded timezone grammar. It is not a general rules/eligibility parser,
  LLM integration, or multilingual extraction system. Unsupported or absent facts cannot be
  used to claim a complete, ready competition brief. Some integration fixtures deliberately
  inject richer extraction/validated reports to exercise later stages.
- The new single-source ambiguity guard fails closed through the existing generic normalization
  error. Structured review of multiple values within one source requires a future versioned
  representation; no automatic choice or retry was added.
- App URL guards reject unsafe literal/DNS/redirect targets, but connection-time DNS/routing
  races still require deployment egress controls. This audit does not certify Railway's network
  policy, live provider availability, authentication/rate limiting, or production load capacity.
- OCR timeout checks reject late results and Tesseract's subprocess is bounded. Every synchronous
  PDF/Python operation is not forcibly killed at an exact whole-request wall-clock deadline.
- Candidate search, supported input limits and fixed fixture coverage are bounded. Existing
  observational performance evidence is not an SLA or real-world extraction accuracy metric.
- Mobile persistence/recovery, purchase/restore, physical-device behavior, UI evidence and
  final end-to-end acceptance belong to 7B. No final release-candidate note is created before both audits pass.

The backend runtime at `650d17ff8dabed273ab50ef5d60581697b777367` is the audited 7A
implementation freeze. Any later backend correctness change requires a scoped fix, full backend
regression, and a new audited runtime commit. Major backend feature development is closed for
this candidate; unsupported product capabilities are not silently added to its claims. A later
documentation-only commit does not redefine runtime truth, but it still receives CI and its
exact publication head/run is recorded in the PR metadata.

## CI evidence locator

Each Python CI job uploads `backend-audit-<audited-commit>` for 90 days. `context.json`
records the **actual checkout** hash separately from the GitHub event/merge hash, the run URL,
git objects for backend/tests/scripts/lockfiles, and SHA-256 hashes of both public authorities.
`pytest.xml` names every executed case and skip/failure; `pytest.log`, `ruff.log`,
`repository.log`, `dependencies.txt` and `tesseract.txt` retain the gate output/environment.

The PR body must record the final head, exact run URL and verdict after CI finishes. A later
documentation-only commit still receives its own exact-head CI bundle; neither an earlier
run nor the historic 6A/6B counts substitute for that check.
