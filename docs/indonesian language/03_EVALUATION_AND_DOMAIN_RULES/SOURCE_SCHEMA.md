# Schema Sumber

**Version:** 1.0

## Tujuan
Mendefinisikan kontrak dari evidence kompetisi mentah sampai canonical competition report sambil mempertahankan provenance, uncertainty, scope, dan conflict.

## SourceRecord
Field wajib:
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

Candidate report adalah evidence, bukan source of truth.

## Canonical field state
State yang diperbolehkan:
- VERIFIED
- SINGLE_SOURCE
- CONFLICT
- MISSING
- UNVERIFIED

Canonical field mempertahankan semua evidence pendukung/konflik. Conflict kritis tidak boleh diselesaikan hanya berdasarkan confidence.

## CanonicalCompetitionReport
Field inti:
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

## Otoritas
Authority is contextual, not merely numeric. Matching official legal/rules text generally outranks summary copy; a newer scoped organizer update may supersede an older deadline when the scope matches.

## Koreksi manusia
Human review may resolve or amend a field. The correction must be auditable and must not erase the original evidence history.