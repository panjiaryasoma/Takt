# Repo Execution Plan v1.0 — Draft

## Monorepo
```text
/
├── apps/
│   ├── mobile/              # Flutter / Dart
│   └── api/                 # FastAPI / Python
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
├── tests/
│   ├── triage/
│   ├── integration/
│   ├── source/
│   ├── solver/
│   └── fixtures/
├── data/
│   ├── fixtures/
│   └── snapshots/
└── docs/
```

## Stack baseline
- Flutter + Dart
- SQLite/Drift local persistence
- Python 3.12+
- FastAPI + Pydantic
- REST/JSON
- OR-Tools CP-SAT
- PyMuPDF/PyMuPDF4LLM + OCR adapter
- RevenueCat

## Candidate API
```text
POST /api/v1/sources/analyze
POST /api/v1/competitions/reconcile
POST /api/v1/triage
POST /api/v1/plans/evaluate
POST /api/v1/plans/recommend
POST /api/v1/plans/re-evaluate
GET  /api/v1/health
```

Payload semantics are contract-bound even if endpoint names change.

## Definition of done
A module is done when schema validates, acceptance tests pass, failure states are defined, provenance/trace exists where required, and no hidden fallback bypasses the contract.
