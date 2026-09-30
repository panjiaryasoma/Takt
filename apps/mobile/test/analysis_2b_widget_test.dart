import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:takt_mobile/data/remote/competition_api_client.dart';
import 'package:takt_mobile/data/repositories/analysis_repository.dart';
import 'package:takt_mobile/models/analysis_snapshot.dart';
import 'package:takt_mobile/models/competition_analysis_wire.dart';
import 'package:takt_mobile/screens/analisis_kompetisi_screen.dart';
import 'package:takt_mobile/screens/progres_analisis_screen.dart';
import 'package:takt_mobile/screens/review_brief_screen.dart';
import 'package:takt_mobile/theme/app_theme.dart';
import 'package:takt_mobile/viewmodels/analisis_view_model.dart';

void main() {
  testWidgets('2B input exposes only PDF or URL and no fake analysis goal',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: AnalisisKompetisiScreen(
            continuation: false,
          ),
        ),
      ),
    );

    expect(find.text('Upload PDF'), findsOneWidget);
    expect(find.text('Enter Link'), findsOneWidget);
    expect(find.text('Select source type'), findsOneWidget);
    expect(find.textContaining('Analysis Goal'), findsNothing);
    expect(find.textContaining('Foto'), findsNothing);
    expect(tester.takeException(), isNull);
  });


  testWidgets('submit stays disabled until the selected source is valid',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: AnalisisKompetisiScreen(
            continuation: false,
          ),
        ),
      ),
    );

    FilledButton submitButton() => tester.widget<FilledButton>(
          find.byKey(const Key('submit-analysis')),
        );

    expect(submitButton().onPressed, isNull);

    await tester.tap(find.text('Enter Link'));
    await tester.pump();
    expect(submitButton().onPressed, isNull);

    await tester.tap(find.byType(DropdownButton<SourceTypeWire>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Official rules').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'not-a-url',
    );
    await tester.pump();
    expect(submitButton().onPressed, isNull);

    await tester.enterText(
      find.byType(TextField),
      'https://example.com/rules',
    );
    await tester.pump();
    expect(submitButton().onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('processing screen never invents percent or ETA',
      (tester) async {
    final vm = AnalisisViewModel(
      apiClient: _NoopApiClient(),
      repository: _NoopAnalysisRepository(),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: vm,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: ProgresAnalisisScreen(),
          ),
        ),
      ),
    );

    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('seconds'), findsNothing);
    expect(find.text('Not ready for review'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review renders all truth states and provenance',
      (tester) async {
    final response = _reviewResponse();
    var addSourceCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ReviewBriefScreen(
            response: response,
            onAddSource: () => addSourceCalled = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Report v2'), findsOneWidget);
    expect(find.text('Verified'), findsWidgets);
    expect(find.text('Single source'), findsOneWidget);
    expect(find.text('Conflict'), findsOneWidget);
    expect(find.text('Not found yet'), findsWidgets);
    expect(find.text('Unverified'), findsOneWidget);
    expect(find.text('Candidate 1'), findsWidgets);
    expect(find.text('Candidate 2'), findsOneWidget);
    expect(find.text('View sources'), findsWidgets);

    final scrollable = find.byType(Scrollable).first;
    final firstSource = find.text('View sources').first;
    await tester.scrollUntilVisible(
      firstSource,
      200,
      scrollable: scrollable,
    );
    await tester.tap(firstSource);
    await tester.pumpAndSettle();
    expect(find.text('Show more'), findsOneWidget);

    final addSource = find.text('Add Source');
    await tester.scrollUntilVisible(
      addSource,
      500,
      scrollable: scrollable,
    );
    await tester.tap(addSource);
    await tester.pump();
    expect(addSourceCalled, isTrue);

    expect(find.textContaining('Add Schedule'), findsNothing);
    expect(find.textContaining('Save Schedule'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Source Review remains reachable at 320px and 2x text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: Scaffold(body: ReviewBriefScreen(response: _reviewResponse())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review Sources'), findsOneWidget);
    final plan = find.text('Continue to Planning');
    await tester.scrollUntilVisible(
      plan,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(plan, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

CompetitionAnalyzeResponseWire _reviewResponse() {
  const source = SourceRecordWire(
    sourceId: 'src-1',
    sourceType: SourceTypeWire.officialRules,
    urlOrDocumentId: 'https://example.com/rules',
    retrievedAt: '2026-09-29T05:00:00Z',
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
        rawReference: name == 'competition_name'
            ? List<String>.filled(260, 'x').join()
            : '$name raw evidence',
        fieldName: name,
        extractionPath: 'native',
      ),
    );
    fields[name] = CanonicalFieldWire(
      fieldName: name,
      state: CanonicalFieldState.verified,
      value: '$name value',
      normalizedValue: '$name value',
      candidates: [
        CandidateFieldWire(
          rawValue: '$name value',
          normalizedValue: '$name value',
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
        rawValue: '1 Oct',
        normalizedValue: '2026-10-01T00:00:00Z',
        evidenceIds: ['ev-submission_deadline'],
      ),
      CandidateFieldWire(
        rawValue: '2 Oct',
        normalizedValue: '2026-10-02T00:00:00Z',
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
      sourceId: 'src-1',
      pageOrLocator: 'faq',
      rawReference: 'Deadline 2 Oct',
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
      competitionId: 'cmp-widget',
      reportVersion: 2,
      sourceIds: const ['src-1'],
      canonicalFields: fields,
      unresolvedCriticalFields: const ['submission_deadline'],
    ),
    ref: const CanonicalReportRefWire(
      competitionId: 'cmp-widget',
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

class _NoopApiClient implements CompetitionApiClient {
  @override
  Future<CompetitionAnalysisTransportResult> analyzePdf({
    required String competitionId,
    required String documentId,
    required String filename,
    required Uint8List bytes,
    required AnalysisSourceMetadata source,
    AnalysisContinuationContext? continuation,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<CompetitionAnalysisTransportResult> analyzeUrl({
    required String competitionId,
    required String url,
    required AnalysisSourceMetadata source,
    AnalysisContinuationContext? continuation,
  }) {
    throw UnimplementedError();
  }

  @override
  void close() {}
}

class _NoopAnalysisRepository implements AnalysisRepository {
  @override
  Future<void> close() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<AnalysisSnapshot?> latestSnapshot(
    String competitionId,
  ) async =>
      null;

  @override
  Future<AnalysisSnapshot> persistResponse({
    required String originalBody,
    required CompetitionAnalyzeResponseWire response,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<AnalysisSnapshot>> snapshotsForCompetition(
    String competitionId,
  ) async =>
      const [];
}