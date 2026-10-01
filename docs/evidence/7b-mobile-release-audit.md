# Hari 7B — Mobile + End-to-End Release Audit

Date: 2026-10-01  
Branch: `H-7B`  
Post-7A baseline: `main@17b9459a53b9a051a4e794b3c15ca47737170a32`

## Verdict

**Technical verdict: GO for Hari 7B mobile and end-to-end release correctness.**

The audited runtime/evidence implementation is:

```text
fc064307bea30ff2a4ccdc9d49d67d260b8b8097
```

Exact-head CI run **#296** completed successfully.

Known release blockers after the audit:

```text
P0 / critical               0
P1 / HIGH                   0
public/recovery drift       0 known
trusted truth loss          0 known
critical persistence issue  0 known
```

Hari 7B did not redefine backend/domain semantics or add a major product feature.
The work added release-audit evidence and exact-head mobile CI verification around
the already-frozen mobile behavior.

## Scope audited

The release audit traced the final user-facing and local-persistence path:

```text
Analyze
→ Source Review
→ Planning Setup
→ Decision Report
→ explicit Accept
→ Saved Plans
→ Schedule
→ restart / stale / recovery
```

The audit also covered:

- root navigation and semantic Back behavior;
- schedule CRUD and supported recurrence presentation;
- URL/PDF analysis input states;
- processing, empty, and recoverable failure states;
- source provenance and canonical conflict presentation;
- readiness / feasibility / recommendation hierarchy;
- alternative-candidate presentation without rewriting system-primary truth;
- acceptance as explicit user intent followed by atomic local persistence;
- accepted-plan and task-progress persistence;
- trusted `SUPERSEDED` stale presentation and re-evaluation entry;
- request retry vs local persistence retry separation;
- 320 px width with 2x text-scale critical-path checks;
- Android and iOS debug builds;
- exact-head cross-language recovery authority identity.

## Authority boundaries preserved

The audit retained the frozen H7 invariants:

```text
UNKNOWN != INFEASIBLE
FAILURE != MISSING
EMPTY RESULT != FAILURE
CONFLICT remains CONFLICT

SESSION OUTDATED != SUPERSEDED
trusted stale truth cannot be silently erased

suggestion != commitment
Accept truth exists only after local transaction commit

persistence retry != API retry
client/local failure codes != backend public codes

RevenueCat / entitlement cannot alter correctness truth
```

The test-only release fixtures do not enter application runtime and do not become a
second domain authority.

## Automated release evidence

### Exact-head CI

Run:

```text
CI #296
head fc064307bea30ff2a4ccdc9d49d67d260b8b8097
```

Results:

| Gate | Result |
| --- | --- |
| Repository validator | PASS |
| Python Ruff | PASS |
| Python regression | 1010 passed, 0 failed, 0 skipped |
| Flutter analyze | PASS |
| Flutter regression excluding 7B evidence-only suite | 286 passed |
| 7B compact 320 px / 2x QA | PASS |
| 7B screenshot evidence render | PASS |
| Android debug build | PASS |
| iOS debug build | PASS |
| Mobile release artifact upload | PASS |

### Mobile evidence artifact

Exact-head artifact:

```text
mobile-audit-fc064307bea30ff2a4ccdc9d49d67d260b8b8097
```

The artifact records:

- exact audited commit/tree and mobile tree identity;
- recovery-policy SHA-256;
- Flutter version;
- Flutter analyze log;
- full Flutter regression log;
- compact 320 px / 2x QA log;
- screenshot-render log;
- Android debug-build log;
- synthetic screenshot manifest;
- nine rendered PNG release-evidence states;
- Android debug APK.

### Screenshot evidence set

All screenshot data is synthetic and contains no personal user data.

```text
01-hero-overview.png
02-my-schedule.png
03-analyze-competition.png
04-conflict-provenance.png
05-decision-report.png
06-alternative-candidate.png
07-saved-plan-accepted.png
08-stale-reevaluate.png
09-accepted-commitment.png
```

The evidence states correspond to:

1. product/home overview;
2. My Schedule;
3. Analyze Competition;
4. conflict + provenance review;
5. Decision Report;
6. explicit alternative-candidate selection;
7. accepted Saved Plan;
8. persisted stale / re-evaluate state;
9. accepted commitment block.

The CI checks that exactly nine PNGs are produced before the evidence artifact is
accepted.

## Persistence and recovery evidence

Existing executable mobile tests already cover the correctness-bearing storage and
recovery paths, including:

- fresh Drift database initialization;
- supported v1 → v3 migration preserving commitments;
- analysis snapshots surviving database restart;
- failed Accept transaction remaining rolled back after restart;
- accepted plan, progress, and accepted blocks surviving restart;
- foreign-key integrity after acceptance;
- trusted `SUPERSEDED` preserving the accepted historical revision while marking
  its source evaluation stale;
- pending acceptance remaining non-durable until the local transaction commits;
- post-commit projection-refresh failure not undoing accepted truth;
- analysis persistence retry not repeating the backend request;
- Saved Plans / Schedule local read failures exposing explicit recovery.

No database auto-delete/reset behavior was introduced as a recovery shortcut.

## Responsive and interaction evidence

Executable widget coverage verifies critical controls at 320 px width and 2x text
scale for the release-relevant surfaces, including:

- root navigation;
- Analyze Competition;
- Source Review;
- Add Schedule;
- Decision Report;
- recovery actions;
- Saved Plan re-evaluation recovery.

The H7 compact QA additionally walks all four root tabs at 320 px / 2x and fails on
captured Flutter layout exceptions.

The root shell uses system-safe-area handling and the bottom navigation accounts for
the device bottom inset.

## Findings during 7B

No runtime P0/P1 correctness defect was established during this audit.

The audit did expose release-evidence infrastructure gaps. They were corrected
without changing product/domain semantics:

| Finding | Class | Resolution |
| --- | --- | --- |
| Flutter/iOS PR jobs did not explicitly check out the exact PR-head SHA | P2 / evidence integrity | Both jobs now check out `github.event.pull_request.head.sha || github.sha` |
| No repeatable mobile visual evidence bundle existed | P2 / evidence | Added synthetic test-only fixtures, nine PNG states, manifest and CI artifact |
| Initial release screenshot harness could retain resources / block CI teardown | P2 / test infrastructure | Added bounded pumping, lifecycle-ordered cleanup, separated audit gates and shell-owned manifest creation |
| Monolithic audit test obscured whether regression, compact QA or rendering was blocked | P2 / diagnosability | Full Flutter regression, compact QA and screenshot rendering are separate CI gates |

The final exact-head run verifies the corrected audit infrastructure.

## Demo repeatability

The release evidence is deterministic and test-only:

- fixture domains use `example.test`;
- no account, email, phone number, payment identity, or personal schedule data is
  included;
- accepted/stale fixtures use production model shapes but remain under
  `apps/mobile/test/`;
- evidence regeneration uses the same checked-out commit and the same CI workflow;
- fresh test databases are created from code rather than requiring manual patching.

This proves a repeatable synthetic release demonstration path. It does not claim that
arbitrary external competition websites will always produce the same extraction
result.

## Known non-blocking limitations

The following are intentionally **not** upgraded into stronger claims:

- CI screenshots are Flutter test-renderer evidence, not exhaustive physical-device
  visual certification.
- Android/iOS evidence is debug-build compilation, not signed Play Store/TestFlight
  distribution certification.
- Real RevenueCat purchase/restore against a physical store account is outside this
  exact CI evidence. Existing tests verify entitlement/presentation boundaries and
  failure handling, but not a live store transaction.
- In-memory unsaved responses are not claimed to survive arbitrary OS process death.
- 320 px / 2x coverage targets critical paths and does not prove every possible
  locale, accessibility setting, device ratio, or OEM system UI.
- Synthetic screenshots prove presentation of controlled states; they are not a
  substitute for final human crop/marketing review if submission artwork is edited
  outside the app.
- Backend deployment-network behavior and live external-source extraction remain
  outside 7B; 7A owns backend release correctness evidence.

These limitations are non-blocking for the audited mobile correctness scope.

## Freeze rule

The mobile runtime/evidence implementation at
`fc064307bea30ff2a4ccdc9d49d67d260b8b8097` is the Hari 7B audited runtime
freeze.

Any later runtime correctness change requires:

```text
scoped fix
→ mobile regression
→ 7B compact QA
→ screenshot evidence regeneration
→ Android/iOS build
→ exact-head re-audit
```

A later documentation-only commit does not redefine runtime truth, but its PR head
must still receive green CI. The exact publication head/run is recorded in PR #37
metadata to avoid a self-staling documentation loop.

## Release boundary

Hari 7B is GO for its mobile/end-to-end release-audit scope.

Whole-product release evidence should only be considered complete when the already
merged Hari 7A GO evidence and this Hari 7B GO evidence are both present on
`main`. PR #37 remains unmerged until separate explicit merge approval.
