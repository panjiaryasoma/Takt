# Keputusan Finalisasi Schema

**Keputusan:** TERIMA baseline schema v1.0.0 untuk implementation handoff.

Contract yang diterima: `CompetitionBrief`, `ReadinessTriage`, `Task`, `AvailabilityBlock`, `CandidateAllocation`, `Recommendation`, `DecisionSupportReport`.

Ditolak:
- one giant `AnalysisResult` because it hides authority/state boundaries;
- solver-generated final calendar because candidate allocation is not user commitment;
- binary-only eligibility because missing/conflicting information needs review states;
- scalar task difficulty because workload ranges/dependencies are more actionable.

Tingkat freeze: behavioral freeze, not implementation freeze. Versioned changes remain possible when integration evidence exposes a real contradiction.
