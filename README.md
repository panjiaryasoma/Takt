# Takt

Calendar-aware competition decision support.

Takt turns competition rules into a provenance-backed brief, evaluates them against a user's real calendar, generates feasible candidate allocations, and explains recommendations without silently scheduling the user's life.

## Monorepo

```text
.
├── apps/
│   ├── api/          # FastAPI backend
│   └── mobile/       # Flutter client
├── engine/
│   ├── extraction/
│   ├── reconciliation/
│   ├── triage/
│   ├── workload/
│   ├── availability/
│   ├── scheduler/
│   └── recommendation/
├── packages/
│   └── contracts/
├── scripts/
├── tests/
└── docs/
```

## Backend quick start

Requires Python 3.12 and `uv`.

```bash
uv sync --locked --dev
uv run uvicorn apps.api.main:app --reload
```

Health check:

```text
GET http://127.0.0.1:8000/health
```

Run backend quality checks:

```bash
uv run ruff check apps engine packages tests scripts
uv run pytest -q
```

On Windows, run the same quality gate with:

```powershell
.\scripts\verify_backend.ps1
```

## Mobile bootstrap

The Flutter source scaffold lives in `apps/mobile/`. If platform runners are not present yet:

```bash
cd apps/mobile
flutter create . --platforms=android,ios
flutter pub get
flutter run
```

## Behavioral authority

Implementation must follow:

```text
docs/05_PREPRODUCTION/01_CONTRACTS_ACTIVE/
docs/03_EVALUATION_AND_DOMAIN_RULES/domain_rules_v1.0.yaml
docs/03_EVALUATION_AND_DOMAIN_RULES/SOURCE_SCHEMA.md
```

Key invariant: recommendation is advisory; commitment requires explicit user action.


## RevenueCat / Takt Pro

RevenueCat is an access boundary only. It does not change Takt's competition
facts, readiness, feasibility, planning inputs, solver output, recommendation
truth, or persisted accepted-plan history.

Canonical 4C identifiers:

```text
entitlement: pro
Test Store product: takt_pro_lifetime_v1
offering: default
package: $rc_lifetime
premium feature: alternative_candidates
```

For the Shipaton Android demo, copy the committed example into an ignored local
configuration file and insert the RevenueCat public Test Store SDK key:

```bash
cd apps/mobile
cp config/revenuecat.test.example.json config/revenuecat.test.local.json
flutter run --debug \
  --dart-define-from-file=config/revenuecat.test.local.json
```

Test Store configuration is accepted only for debug builds. Production Android
configuration accepts only a public `goog_` SDK key. Secret `sk_` keys must
never be embedded in the client or committed to the repository.

The free experience keeps the primary recommendation and all domain facts
available. An active `pro` entitlement unlocks the Alternative Candidate
Explorer, including viewing and selecting additional valid candidates returned
by the same backend evaluation. Unknown or initial entitlement failures fail
closed. Refresh failures preserve the last trustworthy entitlement state.

Purchase and restore use RevenueCat's official Flutter SDK. The demo path uses
the RevenueCat Test Store; Google Play production setup remains a separate
deployment concern.

Mobile regression gate:

```bash
cd apps/mobile
flutter analyze
flutter test
flutter build apk --debug
```
