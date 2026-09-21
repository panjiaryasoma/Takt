# Stakeholder Map & Monorepo Ownership v1.0

## Principle
Ownership follows module boundaries. Every critical area has a primary owner, reviewer, and explicit change authority.

## Internal roles
- **Product/System Owner:** product thesis, scope, authority boundaries, cut scope.
- **Mobile/Frontend Owner:** `apps/mobile/`, Flutter UX, local state, RevenueCat client.
- **Backend/Domain Owner:** `apps/api/` and domain orchestration.
- **Extraction Owner:** `engine/extraction/`, `engine/reconciliation/`, source provenance.
- **Scheduling Owner:** `engine/availability/`, `engine/scheduler/`, CP-SAT invariants.
- **Recommendation Owner:** `engine/recommendation/`, ranking/explanation semantics.
- **Contracts Owner:** `packages/contracts/`, shared DTO/schema/versioning.
- **QA/Evaluation Owner:** `tests/`, fixtures, release-blocking contract evidence.
- **Entitlement Integration:** RevenueCat purchase/restore/gating without correctness authority.

## External stakeholders
End user retains final participation and commitment authority. Competition organizer is authoritative for rules. Judges evaluate the submission but do not control runtime logic. Third-party providers are replaceable infrastructure dependencies.

## Ownership matrix
| Area | Primary | Reviewer |
|---|---|---|
| apps/mobile | Mobile | Product + Contracts |
| apps/api | Backend | Contracts + QA |
| engine/extraction | Extraction | Backend + QA |
| engine/reconciliation | Extraction | Contracts + QA |
| engine/triage | Backend/Domain | Product + QA |
| engine/workload | Backend/Domain | Product |
| engine/availability | Scheduling | Backend + QA |
| engine/scheduler | Scheduling | QA |
| engine/recommendation | Recommendation | Product + QA |
| packages/contracts | Contracts | Mobile + Backend + Product |
| tests | QA | module owner |
| data/fixtures | QA | Domain owner |
| data/snapshots | Extraction/QA | Product |
| docs | Product/System | all owners |

## Two-person team mapping
**Owner A — System / Backend / AI:** apps/api, engine, packages/contracts, domain/integration tests.

**Owner B — Product / Mobile / UI:** apps/mobile, local persistence, calendar UX, RevenueCat client, mobile tests.

**Shared:** contracts review, docs, integration tests, release decision. Neither owner changes shared contracts unilaterally.

## Merge policy
Internal-only changes may merge with module tests. Shared DTO/enum/API/canonical/triage/solver-contract changes require cross-owner review. Critical contract changes require a Schema Change Request plus regression fixture.

## CODEOWNERS concept
```text
/apps/mobile/                  @mobile-owner
/apps/api/                     @backend-owner
/engine/extraction/            @extraction-owner
/engine/reconciliation/        @extraction-owner @backend-owner
/engine/triage/                @backend-owner @qa-owner
/engine/scheduler/             @scheduler-owner @qa-owner
/engine/recommendation/        @backend-owner @product-owner
/packages/contracts/           @contract-owner @backend-owner @mobile-owner
/tests/                        @qa-owner
/docs/                         @product-owner
```
