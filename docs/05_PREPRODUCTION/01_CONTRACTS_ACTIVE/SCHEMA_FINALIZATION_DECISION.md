# Schema Finalization Decision

**Decision:** ACCEPT baseline schema v1.0.0 for implementation handoff.

Accepted contracts: `CompetitionBrief`, `ReadinessTriage`, `Task`, `AvailabilityBlock`, `CandidateAllocation`, `Recommendation`, `DecisionSupportReport`.

Rejected:
- one giant `AnalysisResult` because it hides authority/state boundaries;
- solver-generated final calendar because candidate allocation is not user commitment;
- binary-only eligibility because missing/conflicting information needs review states;
- scalar task difficulty because workload ranges/dependencies are more actionable.

Freeze level: behavioral freeze, not implementation freeze. Versioned changes remain possible when integration evidence exposes a real contradiction.
