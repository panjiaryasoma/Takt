import 'package:takt_mobile/data/repositories/saved_plan_repository.dart';
import 'package:takt_mobile/models/accepted_commitment.dart';
import 'package:takt_mobile/models/competition_analysis_wire.dart';
import 'package:takt_mobile/models/enums.dart';
import 'package:takt_mobile/models/saved_plan.dart';
import 'package:takt_mobile/models/saved_plan_revision.dart';
import 'package:takt_mobile/models/saved_plan_task.dart';
import 'package:takt_mobile/models/task_progress.dart';

CompetitionAnalyzeResponseWire releaseConflictReviewFixture() {
  const source = SourceRecordWire(
    sourceId: 'src-official-rules',
    sourceType: SourceTypeWire.officialRules,
    urlOrDocumentId: 'https://example.test/demo-rules',
    retrievedAt: '2026-10-01T05:00:00Z',
  );
  final evidence = <EvidenceSpanWire>[];
  final fields = <String, CanonicalFieldWire>{};

  for (final name in coreCanonicalFieldNames) {
    final evidenceId = 'ev-$name';
    evidence.add(
      EvidenceSpanWire(
        evidenceId: evidenceId,
        sourceId: source.sourceId,
        pageOrLocator: 'section:$name',
        rawReference: '$name synthetic evidence',
        fieldName: name,
        extractionPath: 'native',
      ),
    );
    fields[name] = CanonicalFieldWire(
      fieldName: name,
      state: CanonicalFieldState.verified,
      value: name == 'competition_name' ? 'Demo Hackathon' : '$name value',
      normalizedValue:
          name == 'competition_name' ? 'Demo Hackathon' : '$name value',
      candidates: [
        CandidateFieldWire(
          rawValue: name == 'competition_name'
              ? 'Demo Hackathon'
              : '$name value',
          normalizedValue: name == 'competition_name'
              ? 'Demo Hackathon'
              : '$name value',
          evidenceIds: [evidenceId],
        ),
      ],
      evidenceIds: [evidenceId],
    );
  }

  final organizer = fields['organizer']!;
  fields['organizer'] = CanonicalFieldWire(
    fieldName: organizer.fieldName,
    state: CanonicalFieldState.singleSource,
    value: organizer.value,
    normalizedValue: organizer.normalizedValue,
    candidates: organizer.candidates,
    evidenceIds: organizer.evidenceIds,
  );

  final eligibility = fields['eligibility']!;
  fields['eligibility'] = CanonicalFieldWire(
    fieldName: eligibility.fieldName,
    state: CanonicalFieldState.unverified,
    value: null,
    normalizedValue: null,
    candidates: eligibility.candidates,
    evidenceIds: eligibility.evidenceIds,
  );

  fields['submission_deadline'] = const CanonicalFieldWire(
    fieldName: 'submission_deadline',
    state: CanonicalFieldState.conflict,
    value: null,
    normalizedValue: null,
    candidates: [
      CandidateFieldWire(
        rawValue: 'October 10 2026 at 23:00 WIB',
        normalizedValue: '2026-10-10T16:00:00Z',
        evidenceIds: ['ev-submission_deadline'],
      ),
      CandidateFieldWire(
        rawValue: 'October 11 2026 at 23:00 WIB',
        normalizedValue: '2026-10-11T16:00:00Z',
        evidenceIds: ['ev-submission-deadline-alt'],
      ),
    ],
    evidenceIds: [
      'ev-submission_deadline',
      'ev-submission-deadline-alt',
    ],
  );
  evidence.add(
    const EvidenceSpanWire(
      evidenceId: 'ev-submission-deadline-alt',
      sourceId: 'src-official-rules',
      pageOrLocator: 'faq:deadline',
      rawReference: 'Synthetic FAQ deadline alternative',
      fieldName: 'submission_deadline',
      extractionPath: 'native',
    ),
  );

  fields['registration_deadline'] = const CanonicalFieldWire(
    fieldName: 'registration_deadline',
    state: CanonicalFieldState.missing,
    value: null,
    normalizedValue: null,
    candidates: [],
    evidenceIds: [],
  );

  return CompetitionAnalyzeResponseWire(
    report: CanonicalCompetitionReportWire(
      competitionId: 'competition-demo',
      reportVersion: 2,
      sourceIds: const ['src-official-rules'],
      canonicalFields: fields,
      unresolvedCriticalFields: const ['submission_deadline'],
    ),
    ref: const CanonicalReportRefWire(
      competitionId: 'competition-demo',
      reportVersion: 2,
      assemblyMaterialFingerprint:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      sourceSetFingerprint:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      wireFingerprint:
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
    ),
    provenance: AnalysisProvenanceWire(
      sources: [source],
      evidence: evidence,
    ),
    reportChanged: true,
  );
}

SavedPlanSummary releaseSavedPlanSummary({required bool stale}) {
  final acceptedAt = DateTime.utc(2026, 10, 1, 6).millisecondsSinceEpoch;
  final plan = SavedPlan(
    id: 'saved-plan-demo',
    competitionId: 'competition-demo',
    createdAtEpochMs: acceptedAt,
    updatedAtEpochMs: acceptedAt,
  );
  final revision = SavedPlanRevision(
    id: 'revision-demo',
    savedPlanId: plan.id,
    revisionNumber: 1,
    evaluationId: '11111111-1111-4111-8111-111111111111',
    selectedCandidateId: 'primary-option',
    selectionSource: SelectionSource.primary,
    acceptedAtEpochMs: acceptedAt,
  );
  return SavedPlanSummary(
    plan: plan,
    currentRevision: revision,
    title: 'Demo Hackathon',
    deadline: DateTime.utc(2026, 10, 10, 16),
    stale: stale,
  );
}

SavedPlanDetail releaseSavedPlanDetail({required bool stale}) {
  final summary = releaseSavedPlanSummary(stale: stale);
  final revision = summary.currentRevision;
  final task = SavedPlanTask(
    id: 'saved-task-demo',
    savedPlanRevisionId: revision.id,
    domainTaskId: 'task-draft',
    ordinal: 0,
    name: 'Build prototype',
    mandatory: true,
    effortMinMinutes: 30,
    effortLikelyMinutes: 60,
    effortMaxMinutes: 90,
    dependenciesJson: '[]',
    assumptionsJson: '["Synthetic demo task"]',
    taskPayloadJson: '{"task_id":"task-draft"}',
  );
  final progress = TaskProgress(
    savedPlanTaskId: task.id,
    progressPercent: 65,
    actualMinutes: 50,
    updatedAtEpochMs: DateTime.utc(2026, 10, 1, 7).millisecondsSinceEpoch,
  );
  final start = DateTime.utc(2026, 10, 2, 12);
  final accepted = AcceptedCommitment(
    id: 'accepted-demo',
    savedPlanRevisionId: revision.id,
    savedPlanTaskId: task.id,
    sourceBlockOrdinal: 0,
    startAtEpochMs: start.millisecondsSinceEpoch,
    endAtEpochMs: start.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
    allocatedMinutes: 30,
    originalAvailabilitySource: 'synthetic-work-window',
    sourceBlockJson:
        '{"task_id":"task-draft","allocated_minutes":30,"availability_source":"synthetic-work-window"}',
    acceptedAtEpochMs: revision.acceptedAtEpochMs,
  );

  return SavedPlanDetail(
    summary: summary,
    revisions: [revision],
    tasks: [SavedPlanTaskState(task: task, progress: progress)],
    acceptedCommitments: [accepted],
  );
}
