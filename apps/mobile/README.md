# Takt Mobile

Flutter source scaffold.

If Android/iOS runner directories have not been generated on your machine:

```bash
flutter create . --platforms=android,ios
flutter pub get
flutter test
flutter run
```

Do not let generated calendar UI blur the authority boundary:

```text
suggested work window != accepted commitment
```

## 3B Decision Report

3B owns strict response parsing, the immutable evaluation session, report presentation,
candidate selection, confirmation, and decision intents. The screen reuses the
existing Steffi theme and card layout. It has no HTTP client or database dependency.

The 4B integration host supplies `decisionSession`, `currentInputRevision`,
`onAcceptCandidate`, `onEditConstraints`, and `onIgnoreRecommendation` to `TaktApp`
(or supplies the equivalent inputs directly to `RekomendasiJadwalScreen`).
Without a session, the existing 2B analysis flow remains available. Tests use
explicit wire fixtures under `test/support`; production never installs a demo session.
Both backend and Flutter tests also read the same contract golden at
`tests/fixtures/api/plan_evaluate_response_v1.json` (from the repository root).
The backend validates that JSON and compares it with `evaluate_plan` output using
the fixed request, clock and evaluation ID in `test_plan_evaluate_behavior.py`;
Flutter parses the file unchanged. Update it deliberately with any wire contract
change. This checks producer/consumer compatibility; real API integration remains
part of 4B.

Host contract:

- Own authoritative inputs, request generation, late-response rejection and active
  session replacement. Pair the exact request/response and check report/snapshot
  identity before publishing `EvaluationSession.fromRaw(...)`.
- `fromRaw` is the only session constructor. The original request is opaque to 3B;
  the original response is parsed internally into deeply immutable DTOs.
- Push the current input revision into the component when authoritative inputs
  change. Invalidated sessions cannot regain action authority without replacement.
- Replacing a session cancels pending confirmation even at the same input revision.
  Confirmation freezes the session, generation, evaluation and candidate identity.
- Accept receives the exact session and intent once per confirmed handoff. 4B must
  revalidate active session/revision at its persistence boundary and own persistent
  idempotency. Callback completion does not authorize a 3B "saved/booked" claim.
- Edit Constraints emits an intent. 4B opens its real editor, changes inputs, bumps
  revision, evaluates, and publishes a new session. Ignore dismisses the suggestion.

Readiness and feasibility stay separate. Blocked readiness explains its specific
gate (review, missing information, unmet eligibility or passed deadline), while
feasibility remains unevaluated. Primary recommendation never changes when
the user selects an alternative. Only backend-allowed actions are rendered; missing
host handlers disable Accept/Edit rather than silently pretending success.
Timestamps are shown in device local time with explicit UTC offsets.

HTTP, planning-input assembly, workload/availability generation, authoritative
constraint mutation, persistence, Saved Plans and re-evaluation remain 4B work.
Issue #7 component behavior can be tested here; real edit-to-evaluate and the
Technical MVP end-to-end remain dependent on that host.

Verification: `flutter analyze`, `flutter test`, `flutter build apk --debug`, and
the existing backend regression suite. Results must be associated with the tested
commit, not inherited from an earlier baseline.

## RevenueCat configuration contract

RevenueCat is a mobile-owned access dependency. It must never change deadline,
eligibility, source-conflict, feasibility, solver, or recommendation truth.

The canonical identifiers are:

```text
entitlement: pro
Test Store product: takt_pro_lifetime_v1
Offering identifier: default
lifetime package: $rc_lifetime
premium feature: alternative_candidates
```

The Shipaton demo path uses RevenueCat Test Store on Android. Google Play
provider setup and credentials are deferred.

Create an ignored local Test Store config from the committed example:

```bash
cp config/revenuecat.test.example.json config/revenuecat.test.local.json
```

Replace the placeholder with the RevenueCat public Test Store SDK key, then
run the debug build with:

```bash
flutter run --debug \
  --dart-define-from-file=config/revenuecat.test.local.json
```

Test Store config is intentionally rejected for profile and release builds.
Production Android config accepts only a public `goog_` SDK key.

Never put RevenueCat secret `sk_` keys in the app or repository. Do not commit
`*.local.json` config files.

This branch keeps monetization at the access/presentation boundary. RevenueCat
must not change planning inputs, solver feasibility, candidate validity, backend
allowed actions, accepted-plan truth, or local domain persistence.


### RevenueCat runtime foundation

4C Block 2 uses the official `purchases_flutter` SDK. Startup configures RevenueCat
once with the public key and no custom App User ID, so RevenueCat owns the anonymous
identity. The runtime then reads `CustomerInfo` and resolves the canonical
`default` / `$rc_lifetime` package from Offerings.

Entitlement and offering refresh failures preserve the last trustworthy state.
Missing offerings/packages stay explicitly empty; the app never invents a package.
Purchase, restore, paywall UI, and final Decision Report gating remain later 4C work.


### RevenueCat purchase and restore flow

The Home screen exposes a **Takt Pro** entry point when RevenueCat configuration
is available. The custom purchase screen resolves the canonical
`default` / `$rc_lifetime` package from RevenueCat before purchase and uses
the official `Purchases.purchase(PurchaseParams.package(...))` flow.

Purchase outcomes are explicit:
- success activates access only when the returned CustomerInfo contains `pro`;
- cancellation is non-fatal and leaves existing access unchanged;
- pending purchase is shown as pending and does not invent premium access;
- failures preserve the last trustworthy entitlement state.

Restore uses `Purchases.restorePurchases()` and applies the returned
CustomerInfo. A successful restore with no `pro` entitlement remains a valid
non-premium state.

For the Test Store demo:

```powershell
flutter run --dart-define-from-file=config/revenuecat.test.local.json
```

Open **Home → Takt Pro**, complete the Test Store lifetime purchase, then verify
that the screen reports the active `pro` entitlement. Do not commit the local
config file or any store/server credentials.
