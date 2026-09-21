# Source Schema

**Version:** 1.0

## Purpose
Define the contract from raw competition evidence to a canonical competition report while preserving provenance, uncertainty, scope, and conflict.

## SourceRecord
Required fields:
- `source_id`
- `source_type`: official_rules | official_organizer | official_faq | platform | secondary | derived_fixture
- `url_or_document_id`
- `retrieved_at`
- `content_hash`
- `authority_rank`
- `scope`
- `freshness_metadata`

## EvidenceSpan
Required fields:
- `evidence_id`
- `source_id`
- `page_or_locator`
- `raw_text_or_visual_reference`
- `field_name`
- `extraction_path`: native | ocr | vision | manual
- `extractor_version`

## CandidateExtractionReport
Each extraction path emits the same field shape:

```yaml
field_name:
  raw_value: ...
  normalized_value: ...
  evidence_ids: [...]
  extraction_path: native | ocr | vision
  confidence: optional
  scope: ...
```

Candidate reports are evidence, not the source of truth.

## Canonical field state
Allowed states:
- VERIFIED
- SINGLE_SOURCE
- CONFLICT
- MISSING
- UNVERIFIED

A canonical field retains all supporting/conflicting evidence IDs. Critical conflicts cannot be resolved by confidence alone.

## CanonicalCompetitionReport
Core fields:
- competition_name
- organizer
- submission_deadline
- registration_deadline
- eligibility
- team_size
- format
- location
- tracks_or_categories
- deliverables
- required_technologies
- judging_criteria
- prizes_or_benefits
- source_ids
- unresolved_critical_fields

## Authority
Authority is contextual, not merely numeric. Matching official legal/rules text generally outranks summary copy; a newer scoped organizer update may supersede an older deadline when the scope matches.

## Human correction
Human review may resolve or amend a field. The correction must be auditable and must not erase the original evidence history.