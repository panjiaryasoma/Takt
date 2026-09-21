# Keputusan Toolchain

**Status:** baseline dipilih; provider tetap dapat diganti di balik interface.

- **Mobile:** Flutter + Dart.
- **Local persistence:** SQLite via Drift or equivalent typed wrapper.
- **Backend:** Python 3.12+ + FastAPI + Pydantic.
- **Optimization:** Google OR-Tools CP-SAT.
- **PDF:** PyMuPDF / PyMuPDF4LLM.
- **OCR:** adapter boundary supporting Tesseract, RapidOCR, or equivalent.
- **AI/LLM:** provider abstraction; provider/model not frozen.
- **Entitlement:** RevenueCat, isolated from correctness-critical rules.
- **API:** REST/JSON baseline.
- **Deployment:** modular monolith for MVP; no microservice requirement.

Recommended monorepo:
```text
apps/mobile
apps/api
engine/extraction
engine/reconciliation
engine/triage
engine/workload
engine/availability
engine/scheduler
engine/recommendation
packages/contracts
tests
data
docs
```

Ditolak untuk MVP: service mesh, Kafka, unnecessary vector DB, custom ML service without defensible real data, autonomous browser agent as the primary ingestion path.
