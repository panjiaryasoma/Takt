# Takt

Calendar-aware competition decision support.

Takt turns competition rules into a provenance-backed brief, evaluates them against a user's real calendar, generates feasible candidate allocations, and explains recommendations without silently scheduling the user's life.

## Monorepo

```text
.
├── apps/
│   ├── api/          # FastAPI backend
│   └── mobile/       # Flutter client + SQLite/Drift user state
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

```bash
python -m venv .venv
# Windows
.venv\Scripts\activate
# macOS/Linux
source .venv/bin/activate

pip install -e ".[dev]"
python scripts/validate_repo.py
ruff check apps engine packages tests scripts
pytest -q
uvicorn apps.api.main:app --reload
```

Health check:

```text
GET http://127.0.0.1:8000/health
```

## Mobile bootstrap

The Flutter client is local-first. SQLite + Drift is the primary persistence layer for personal user state; the FastAPI backend remains a stateless compute layer for the MVP.

If platform runners are not present yet:

```bash
cd apps/mobile
flutter create . --platforms=android,ios
```

From a clean clone, install dependencies and generate the Drift schema before analyzing or testing:

```bash
cd apps/mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

The generated `app_database.g.dart` file is build output and is intentionally not the source of truth. The schema lives in:

```text
apps/mobile/lib/data/local/app_database.dart
```

Shared mobile wire values live in:

```text
apps/mobile/lib/domain/contracts.dart
```

## Behavioral authority

Implementation must follow:

```text
docs/05_PREPRODUCTION/01_CONTRACTS_ACTIVE/
docs/03_EVALUATION_AND_DOMAIN_RULES/domain_rules_v1.0.yaml
docs/03_EVALUATION_AND_DOMAIN_RULES/SOURCE_SCHEMA.md
docs/indonesian language/06_IMPLEMENTATION_HANDOFF/DATABASE_ARCHITECTURE.md
```

Core invariants:

```text
recommendation != commitment
candidate allocation != final schedule
missing actual effort != zero effort
brief updates create new versions
available blocks are derived state
```

Recommendation is advisory; commitment requires explicit user action.
