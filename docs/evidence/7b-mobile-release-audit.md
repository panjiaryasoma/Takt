# Hari 7B — Mobile + End-to-End Release Audit

Date: 2026-10-01  
Branch: `H-7B`  
Post-7A baseline: `main@17b9459a53b9a051a4e794b3c15ca47737170a32`

## Verdict

**Technical verdict: GO for Hari 7B mobile and end-to-end release correctness.**

The audited runtime/evidence implementation freeze is:

```text
ab44fbe1776afe1a04adeb028aaef6c0e2017622
```

Exact-head CI run **#300** completed successfully.

Known release blockers after the full final audit:

```text
P0 / critical               0
P1 / HIGH                   0
public/recovery drift       0 known
trusted truth loss          0 known
critical persistence issue  0 known
major UI blocker            0 known
```

Hari 7B did not redefine backend/domain semantics or add a major product feature.
The work added release-audit evidence, exact-head mobile CI verification, repeatable
synthetic visual evidence, and release-proofing around the already-frozen mobile
behavior.

## Scope audited

The final user-facing and local-persistence path was traced as:

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

The final audit covered:

- root navigation and semantic Back behavior;
- Schedule CRUD, recurrence, cancellation/move presentation, and ICS import boundaries;
- URL/PDF analysis input and processing states;
- canonical field truth states, provenance, and conflict presentation;
- readiness / feasibility / recommendation hierarchy;
- `TIGHT_CAPACITY` and `NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS` fixture behavior;
- alternative candidate presentation without rewriting system-primary truth;
- acceptance as explicit user intent followed by atomic local persistence;
- Saved Plan, task-progress, and accepted-block persistence;
- trusted `SUPERSEDED` stale presentation and re-evaluation entry;
- request retry vs local-persistence retry separation;
- loading, empty, failure, and explicit recovery states;
- 320 px width with 2x text-scale critical-path checks;
- Android and iOS debug builds;
- exact-head recovery-authority identity;
- repeatable synthetic screenshot generation and crop verification.

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

The 7B fixtures live only under `apps/mobile/test/`; application runtime does not
import them and they do not become a second domain authority.

## Exact-head CI evidence

Run:

```text
CI #300
head ab44fbe1776afe1a04adeb028aaef6c0e2017622
run  https://github.com/panjiaryasoma/Takt/actions/runs/36835931718
```

Results:

| Gate | Result |
| --- | --- |
| Repository validator | PASS |
| Python Ruff | PASS |
| Python regression | 1010 passed, 0 failed, 0 skipped |
| Flutter analyze | PASS |
| Flutter regression excluding release-evidence suite | 286 passed |
| 7B compact 320 px / 2x QA | PASS |
| 7B screenshot evidence render | PASS |
| 9 screenshot dimension/crop check | PASS, all 390 × 844 |
| Android debug build | PASS |
| iOS debug build | PASS |
| Mobile release artifact upload | PASS |
| Backend exact-head artifact upload | PASS |

## Mobile evidence artifact

Exact-head artifact:

```text
mobile-audit-ab44fbe1776afe1a04adeb028aaef6c0e2017622
sha256:a90beb3cac37d2d61e450840bbc475f28df46792f40bb6dd444ba0ce17c24fbd
```

The artifact contains:

- exact audited commit/tree and mobile-tree identity;
- recovery-policy SHA-256;
- Flutter/Dart version;
- Flutter analyze log;
- full Flutter regression log;
- compact 320 px / 2x QA log;
- screenshot-render log;
- Android debug-build log;
- synthetic screenshot manifest;
- nine rendered PNG release-evidence states;
- Android debug APK.

The recorded audit identity is:

```text
audited_commit = ab44fbe1776afe1a04adeb028aaef6c0e2017622
audited_tree   = a993709f9b583bed7f0fd292fc7a20470da60d73
mobile_tree    = cdaf2215c8f6af2a859feb0ef01411d39a77e516
recovery SHA   = 6984fd271fdd017319f0a6d9fb0fae1642c98296280322674fa5e47164d97c1a
```

The CI event SHA is separately recorded, so evidence does not confuse the pull-request
merge event with the exact checked-out audit head.

## Screenshot evidence

All visual evidence is synthetic and contains no personal user data.

Every PNG is locked and verified at:

```text
390 × 844
devicePixelRatio = 1
text scale = 1
```

Evidence set:

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

The final artifact was visually reviewed as a set after CI generation. No obvious
overlap, broken crop, or inconsistent viewport remained in the captured states.

The screenshots correspond to:

1. product/home overview;
2. My Schedule;
3. Analyze Competition;
4. conflict + provenance review;
5. Decision Report;
6. explicit alternative-candidate selection;
7. accepted Saved Plan;
8. persisted stale / re-evaluate state;
9. accepted commitment block.

CI fails if the set is not exactly nine PNGs or any PNG differs from the required
390 × 844 viewport.

## Persistence and local-state evidence

Existing executable mobile tests verify:

- fresh Drift database initialization;
- supported v1 → v3 migration preserving commitments;
- supported v2 → v3 migration preserving analysis snapshots;
- commitment persistence after closing and reopening SQLite;
- analysis snapshots surviving database restart;
- failed Accept transactions remaining rolled back after restart;
- accepted plan, task progress, and accepted blocks surviving restart;
- foreign-key integrity after acceptance;
- trusted `SUPERSEDED` preserving accepted historical revision while marking
  its source evaluation stale;
- pending acceptance remaining non-durable until the local transaction commits;
- post-commit projection-refresh failures not undoing accepted truth;
- analysis persistence retry not repeating the backend request;
- Saved Plans / Schedule local read failures exposing explicit recovery.

No database auto-delete/reset behavior is used as a recovery shortcut.

## Screen and interaction evidence

Executable widget coverage verifies the release-relevant presentation:

- **My Schedule:** CRUD, recurrence, cancellation/move presentation, daily/weekly
  navigation, and 320 px / 2x reachability;
- **Analyze Competition:** PDF/URL-only source choices, validation gating, processing
  without invented percentage/ETA, and responsive input;
- **Source Review:** all canonical truth states, provenance, conflict state, and
  responsive presentation;
- **Decision Report:** readiness, feasibility, system primary recommendation,
  alternative selection, explicit Accept confirmation, blocked/infeasible action
  gating, entitlement fail-closed behavior, and 320 px / 2x semantics;
- **Saved Plans:** accepted state, progress persistence, accepted schedule blocks,
  stale presentation, and re-evaluation recovery;
- **Recovery:** retry/discard/reload boundaries remain explicit and policy-derived;
- **Root shell:** all four tabs remain reachable at 320 px / 2x without captured
  Flutter layout exceptions.

The app root uses `SafeArea`, and bottom navigation includes the device bottom inset.

## Loading, empty, and error states

The audit verified that release-critical screens do not depend on an invisible
indefinite state:

- loading states use explicit progress presentation;
- empty Saved Plans and home/schedule states have explicit copy;
- analysis processing avoids fake percent/ETA;
- local read failures expose retry/reload surfaces;
- unknown backend failures fail closed rather than inventing a retry;
- post-commit refresh failures keep committed truth and offer refresh recovery;
- RevenueCat loading/error states fail closed for premium-only alternatives.

## Demo repeatability

The release demo/evidence path is deterministic and test-only:

- default decision fixtures provide the normal/TIGHT path;
- the same fixture family supports infeasible sessions with
  `NOT_FEASIBLE_UNDER_CURRENT_CONSTRAINTS`;
- the 7B release fixture provides conflict/provenance presentation;
- each evidence run creates fresh local test state from code;
- fixture URLs use `example.test`;
- no account, email, phone number, payment identity, or personal schedule data is used;
- screenshots regenerate from the exact checked-out commit;
- no manual source patch is required between evidence states.

“Fresh-state reset” here means a repeatable fresh test/demo state. 7B does **not**
add a production “wipe all user data” button, because that would be a product feature
rather than release-audit evidence.

## Visual consistency audit

The final artifact and shared UI primitives were checked for the Issue #14 visual
freeze criteria:

- typography hierarchy comes from `AppTheme` plus bounded screen-specific sizes;
- common 14/16/20 px card and screen spacing remains consistent;
- primary, outlined, and text buttons use shared Material themes with minimum target
  sizes;
- status pills use the shared `StatusPill` component;
- cards use the shared dark surface hierarchy and accent borders where semantic
  emphasis is needed;
- Material icon usage remains functionally consistent;
- no `TODO`, `FIXME`, Lorem ipsum, or debug placeholder was found in mobile runtime
  UI;
- captured evidence has a locked crop and no obvious clipping/overlap;
- critical narrow/high-text-scale paths are protected by executable tests.

This is a release freeze, not a claim that every pixel on every device has been
physically certified.

## Findings during 7B

No runtime P0/P1 correctness defect was established during the final 7B audit.

Release-evidence findings were classified and handled as follows:

| Finding | Class | Resolution |
| --- | --- | --- |
| Flutter/iOS PR jobs did not explicitly check out exact PR-head SHA | P2 / evidence integrity | Fixed: both jobs check out `github.event.pull_request.head.sha || github.sha` |
| No repeatable mobile visual evidence bundle existed | P2 / evidence | Fixed: synthetic fixtures, nine PNGs, manifest, logs and APK artifact |
| Initial screenshot harness could retain resources / block teardown | P2 / test infrastructure | Fixed: bounded pumping and lifecycle-ordered cleanup |
| Monolithic audit test obscured which release gate was blocked | P2 / diagnosability | Fixed: regression, compact QA and screenshot render are separate CI gates |
| Screenshot captures used inconsistent intrinsic heights | P2 / evidence quality | Fixed: full-frame capture plus CI-enforced 390 × 844 dimensions |
| `release-7b` test tag emitted undeclared-tag warnings | P2 / evidence hygiene | Fixed: declared in `apps/mobile/dart_test.yaml` |
| `file_picker` applies legacy Kotlin Gradle Plugin behavior that Flutter warns may break in a future Flutter version | P2 / dependency maintenance | **Open non-blocking limitation**; current Android debug build passes. Dependency upgrade is intentionally deferred to avoid release-audit dependency drift |

Final count:

```text
P0 found / remaining       0 / 0
P1 found / remaining       0 / 0
P2 findings                7
P2 fixed                   6
P2 documented limitation   1
```

## Known non-blocking limitations

The following are intentionally not upgraded into stronger claims:

- CI screenshots are Flutter test-renderer evidence, not exhaustive physical-device
  visual certification.
- Android/iOS evidence is debug-build compilation, not signed Play Store/TestFlight
  distribution certification.
- Real RevenueCat purchase/restore against a physical store account is outside this
  exact CI evidence.
- In-memory unsaved responses are not claimed to survive arbitrary OS process death.
- 320 px / 2x coverage targets critical paths and does not prove every locale,
  accessibility setting, device ratio, or OEM system UI.
- Synthetic screenshots prove controlled presentation states; submission artwork
  edited outside the app still needs human crop/marketing review.
- Current Flutter emits a future-compatibility warning for the `file_picker`
  plugin's Kotlin Gradle integration. The current Android build succeeds; upgrading
  that dependency is deferred beyond the release-audit freeze.
- Backend deployment-network behavior and arbitrary live external-source extraction
  remain outside 7B; 7A owns backend release-correctness evidence.

These limitations are non-blocking for the audited 7B mobile correctness scope.

## Freeze rule

The mobile runtime/evidence implementation at

```text
ab44fbe1776afe1a04adeb028aaef6c0e2017622
```

is the Hari 7B audited implementation freeze.

Any later runtime or evidence-harness correctness change requires:

```text
scoped fix
→ Flutter regression
→ 7B compact QA
→ screenshot regeneration + dimension verification
→ Android/iOS build
→ exact-head re-audit
```

A later documentation-only commit does not redefine runtime truth. Its exact
publication head and CI run are recorded in PR #37 metadata to avoid a self-staling
documentation loop.

## Release boundary

Hari 7B is **GO** for its mobile/end-to-end release-audit scope.

Whole-product release evidence can be considered present once the already-merged
Hari 7A GO evidence and this 7B GO evidence are both on `main`.

PR #37 remains unmerged until separate explicit merge approval.
