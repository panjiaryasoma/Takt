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
