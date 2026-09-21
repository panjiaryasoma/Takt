# Stakeholder Map & Monorepo Ownership v1.0

## Prinsip
Ownership mengikuti boundary module. Setiap area kritis punya primary owner, reviewer, dan authority perubahan yang jelas.

## Role internal
- **Product/System Owner:** thesis produk, scope, authority boundary, cut scope.
- **Mobile/Frontend Owner:** `apps/mobile/`, Flutter UX, local state, RevenueCat client.
- **Backend/Domain Owner:** `apps/api/` dan domain orchestration.
- **Extraction Owner:** `engine/extraction/`, `engine/reconciliation/`, source provenance.
- **Scheduling Owner:** `engine/availability/`, `engine/scheduler/`, CP-SAT invariant.
- **Recommendation Owner:** `engine/recommendation/`, ranking/explanation semantics.
- **Contracts Owner:** `packages/contracts/`, shared DTO/schema/versioning.
- **QA/Evaluation Owner:** `tests/`, fixture, release-blocking contract evidence.

## Tim dua orang
**Owner A — System / Backend / AI:** apps/api, engine, packages/contracts, domain/integration tests.

**Owner B — Product / Mobile / UI:** apps/mobile, local persistence, calendar UX, RevenueCat client, mobile tests.

**Shared:** contract review, docs, integration tests, release decision. Shared contract tidak boleh diubah sepihak.

## Merge policy
Internal-only change boleh merge dengan module test. Perubahan shared DTO/enum/API/canonical/triage/solver contract wajib cross-owner review. Critical contract change wajib Schema Change Request + regression fixture.
