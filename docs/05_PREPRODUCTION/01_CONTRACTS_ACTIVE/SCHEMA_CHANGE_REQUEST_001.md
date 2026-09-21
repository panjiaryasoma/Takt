# Schema Change Request 001

**Request:** SCR-001  
**Status:** APPROVED

## Change
Promote the earlier descriptive feature inventory into an active implementation contract. Explicitly separate source verification, readiness, feasibility, recommendation, and human commitment; require critical-field provenance; require effort ranges; define `CandidateAllocation` as solver output; require zero hard violations for recommendable candidates; require explicit human acceptance before commitment; defer direct calendar integration and learned historical effort adjustments.

## Why
Without explicit interfaces, implementation could collapse multiple states into one opaque "AI result".

## Migration
The historical feature schema remains for traceability. New implementation contracts use `FEATURE_SCHEMA_FINAL.yaml`. Later semantic changes require a new SCR.
