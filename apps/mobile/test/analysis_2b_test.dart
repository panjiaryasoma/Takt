import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:takt_mobile/data/database/app_database.dart';
import 'package:takt_mobile/data/remote/competition_api_client.dart';
import 'package:takt_mobile/data/repositories/analysis_repository.dart';
import 'package:takt_mobile/data/repositories/drift_analysis_repository.dart';
import 'package:takt_mobile/models/analysis_failure.dart';
import 'package:takt_mobile/models/analysis_snapshot.dart';
import 'package:takt_mobile/models/analysis_step.dart';
import 'package:takt_mobile/models/competition_analysis_wire.dart';
import 'package:takt_mobile/utils/source_identity.dart';
import 'package:takt_mobile/viewmodels/analisis_view_model.dart';

void main() {
  group('2B wire contract', () {
    test('parses the five canonical states fail-closed', () {
      for (final state in CanonicalFieldState.values) {
        expect(
          CanonicalFieldState.fromWire(state.wire),
          state,
        );
      }
      for (final value in ['', 'UNKNOWN', 'verified', ' VERIFIED ']) {
        expect(
          () => CanonicalFieldState.fromWire(value),
          throwsFormatException,
        );
      }
    });


    test('rejects unsupported report policy version', () {
      final raw = jsonDecode(_responseBody('cmp-version'))
          as Map<String, dynamic>;
      final bundle = raw['report_bundle'] as Map<String, dynamic>;
      final ref = bundle['ref'] as Map<String, dynamic>;
      ref['domain_schema_version'] = '99.0.0';

      expect(
        () => CompetitionAnalyzeResponseWire.parse(jsonEncode(raw)),
        throwsFormatException,
      );
    });


    test('rejects report missing any required core field', () {
      final raw = jsonDecode(_responseBody('cmp-missing-core'))
          as Map<String, dynamic>;
      final bundle = raw['report_bundle'] as Map<String, dynamic>;
      final report = bundle['report'] as Map<String, dynamic>;
      final fields =
          report['canonical_fields'] as Map<String, dynamic>;
      fields.remove('organizer');

      expect(
        () => CompetitionAnalyzeResponseWire.parse(jsonEncode(raw)),
        throwsFormatException,
      );
    });

    test('rejects canonical evidence absent from provenance', () {
      final raw = jsonDecode(_responseBody('cmp-dangling-evidence'))
          as Map<String, dynamic>;
      final provenance = raw['provenance'] as Map<String, dynamic>;
      final evidence = provenance['evidence'] as List<dynamic>;
      evidence.removeWhere(
        (item) =>
            (item as Map<String, dynamic>)['evidence_id'] ==
            'ev-organizer',
      );

      expect(
        () => CompetitionAnalyzeResponseWire.parse(jsonEncode(raw)),
        throwsFormatException,
      );
    });

    test('rejects unknown canonical state from backend response', () {
      final raw = jsonDecode(_responseBody('cmp-wire'))
          as Map<String, dynamic>;
      final fields = ((raw['report_bundle']
              as Map<String, dynamic>)['report']
          as Map<String, dynamic>)['canonical_fields']
          as Map<String, dynamic>;
      (fields['competition_name'] as Map<String, dynamic>)['state'] =
          'VERIFIED_V2';

      expect(
        () => CompetitionAnalyzeResponseWire.parse(jsonEncode(raw)),
        throwsFormatException,
      );
    });

    test('conflict cannot expose a canonical value', () {
      final raw = jsonDecode(_responseBody('cmp-conflict'))
          as Map<String, dynamic>;
      final field = _fieldMap(raw, 'submission_deadline');
      field['state'] = 'CONFLICT';
      field['candidates'] = [
        _candidate(
          'submission_deadline',
          '2026-10-01T00:00:00Z',
          'ev-submission_deadline',
        ),
        _candidate(
          'submission_deadline',
          '2026-10-02T00:00:00Z',
          'ev-organizer',
        ),
      ];
      field['evidence_ids'] = [
        'ev-submission_deadline',
        'ev-organizer',
      ];

      expect(
        () => CompetitionAnalyzeResponseWire.parse(jsonEncode(raw)),
        throwsFormatException,
      );
    });


    test('conflict requires normalized candidate disagreement', () {
      final raw = jsonDecode(_responseBody('cmp-conflict-equal'))
          as Map<String, dynamic>;
      final field = _fieldMap(raw, 'submission_deadline');
      field['state'] = 'CONFLICT';
      field['value'] = null;
      field['normalized_value'] = null;
      field['candidates'] = [
        _candidate(
          'submission_deadline',
          '2026-10-01T00:00:00Z',
          'ev-submission_deadline',
        ),
        _candidate(
          'submission_deadline',
          '2026-10-01T00:00:00Z',
          'ev-submission-alt',
        ),
      ];
      field['evidence_ids'] = [
        'ev-submission_deadline',
        'ev-submission-alt',
      ];

      final provenance = raw['provenance'] as Map<String, dynamic>;
      final evidence = provenance['evidence'] as List<dynamic>;
      evidence.add({
        'evidence_id': 'ev-submission-alt',
        'source_id': 'src-1',
        'page_or_locator': 'alternate',
        'raw_text_or_visual_reference': 'same normalized deadline',
        'field_name': 'submission_deadline',
        'extraction_path': 'native',
        'extractor_version': 'test-v1',
      });

      expect(
        () => CompetitionAnalyzeResponseWire.parse(jsonEncode(raw)),
        throwsFormatException,
      );
    });


    test('rejects empty source content_hash', () {
      final raw = jsonDecode(_responseBody('cmp-empty-hash'))
          as Map<String, dynamic>;
      final artifact = _firstSourceArtifact(raw);
      final source = artifact['source'] as Map<String, dynamic>;
      source['content_hash'] = '';

      expect(
        () => CompetitionAnalyzeResponseWire.parse(jsonEncode(raw)),
        throwsFormatException,
      );
    });

    test('rejects candidate report field with empty evidence_ids', () {
      final raw = jsonDecode(_responseBody('cmp-empty-candidate-evidence'))
          as Map<String, dynamic>;
      final report = _firstCandidateReport(raw);
      report['fields'] = [
        _reportCandidateField(
          fieldName: 'organizer',
          evidenceIds: const [],
        ),
      ];

      expect(
        () => CompetitionAnalyzeResponseWire.parse(jsonEncode(raw)),
        throwsFormatException,
      );
    });

    test('rejects duplicate candidate report field_name', () {
      final raw = jsonDecode(_responseBody('cmp-duplicate-field'))
          as Map<String, dynamic>;
      final report = _firstCandidateReport(raw);
      report['fields'] = [
        _reportCandidateField(
          fieldName: 'organizer',
          evidenceIds: const ['report-ev-1'],
        ),
        _reportCandidateField(
          fieldName: 'organizer',
          evidenceIds: const ['report-ev-2'],
        ),
      ];
      report['evidence'] = [
        _reportEvidence(
          evidenceId: 'report-ev-1',
          fieldName: 'organizer',
        ),
        _reportEvidence(
          evidenceId: 'report-ev-2',
          fieldName: 'organizer',
        ),
      ];

      expect(
        () => CompetitionAnalyzeResponseWire.parse(jsonEncode(raw)),
        throwsFormatException,
      );
    });

    test('rejects duplicate candidate report evidence_id', () {
      final raw = jsonDecode(_responseBody('cmp-duplicate-evidence'))
          as Map<String, dynamic>;
      final report = _firstCandidateReport(raw);
      report['evidence'] = [
        _reportEvidence(
          evidenceId: 'report-ev-1',
          fieldName: 'organizer',
        ),
        _reportEvidence(
          evidenceId: 'report-ev-1',
          fieldName: 'organizer',
        ),
      ];

      expect(
        () => CompetitionAnalyzeResponseWire.parse(jsonEncode(raw)),
        throwsFormatException,
      );
    });

    test('rejects candidate extraction path differing from report', () {
      final raw = jsonDecode(_responseBody('cmp-path-mismatch'))
          as Map<String, dynamic>;
      final report = _firstCandidateReport(raw);
      report['fields'] = [
        _reportCandidateField(
          fieldName: 'organizer',
          evidenceIds: const ['report-ev-1'],
          extractionPath: 'ocr',
        ),
      ];
      report['evidence'] = [
        _reportEvidence(
          evidenceId: 'report-ev-1',
          fieldName: 'organizer',
        ),
      ];

      expect(
        () => CompetitionAnalyzeResponseWire.parse(jsonEncode(raw)),
        throwsFormatException,
      );
    });

    test('rejects candidate evidence_id missing from report evidence', () {
      final raw = jsonDecode(_responseBody('cmp-missing-report-evidence'))
          as Map<String, dynamic>;
      final report = _firstCandidateReport(raw);
      report['fields'] = [
        _reportCandidateField(
          fieldName: 'organizer',
          evidenceIds: const ['report-ev-missing'],
        ),
      ];

      expect(
        () => CompetitionAnalyzeResponseWire.parse(jsonEncode(raw)),
        throwsFormatException,
      );
    });

    test('rejects candidate evidence with mismatched field_name', () {
      final raw = jsonDecode(_responseBody('cmp-evidence-field-mismatch'))
          as Map<String, dynamic>;
      final report = _firstCandidateReport(raw);
      report['fields'] = [
        _reportCandidateField(
          fieldName: 'organizer',
          evidenceIds: const ['report-ev-1'],
        ),
      ];
      report['evidence'] = [
        _reportEvidence(
          evidenceId: 'report-ev-1',
          fieldName: 'competition_name',
        ),
      ];

      expect(
        () => CompetitionAnalyzeResponseWire.parse(jsonEncode(raw)),
        throwsFormatException,
      );
    });


    test('rejects empty report source_ids', () {
      final raw = jsonDecode(_responseBody('cmp-empty-sources'))
          as Map<String, dynamic>;
      final bundle = raw['report_bundle'] as Map<String, dynamic>;
      final report = bundle['report'] as Map<String, dynamic>;
      report['source_ids'] = <String>[];

      expect(
        () => CompetitionAnalyzeResponseWire.parse(jsonEncode(raw)),
        throwsFormatException,
      );
    });

    test('rejects duplicate provenance source_id multiplicity', () {
      final raw = jsonDecode(_responseBody('cmp-provenance-duplicate'))
          as Map<String, dynamic>;
      final provenance = raw['provenance'] as Map<String, dynamic>;
      final sources = provenance['sources'] as List<dynamic>;
      sources.add(Map<String, dynamic>.from(
        sources.first as Map<String, dynamic>,
      ));

      expect(
        () => CompetitionAnalyzeResponseWire.parse(jsonEncode(raw)),
        throwsFormatException,
      );
    });

    test('rejects empty provenance extraction run source_id', () {
      final raw = jsonDecode(_responseBody('cmp-run-source'))
          as Map<String, dynamic>;
      _firstProvenanceRun(raw)['source_id'] = '';

      expect(
        () => CompetitionAnalyzeResponseWire.parse(jsonEncode(raw)),
        throwsFormatException,
      );
    });

    test('rejects empty provenance extraction run snapshot_id', () {
      final raw = jsonDecode(_responseBody('cmp-run-snapshot'))
          as Map<String, dynamic>;
      _firstProvenanceRun(raw)['snapshot_id'] = '';

      expect(
        () => CompetitionAnalyzeResponseWire.parse(jsonEncode(raw)),
        throwsFormatException,
      );
    });

    test('rejects empty provenance extraction run extractor_version', () {
      final raw = jsonDecode(_responseBody('cmp-run-version'))
          as Map<String, dynamic>;
      _firstProvenanceRun(raw)['extractor_version'] = '';

      expect(
        () => CompetitionAnalyzeResponseWire.parse(jsonEncode(raw)),
        throwsFormatException,
      );
    });

    test('rejects unknown provenance extraction path', () {
      final raw = jsonDecode(_responseBody('cmp-run-path'))
          as Map<String, dynamic>;
      _firstProvenanceRun(raw)['extraction_path'] = 'magic';

      expect(
        () => CompetitionAnalyzeResponseWire.parse(jsonEncode(raw)),
        throwsFormatException,
      );
    });

    test('accepts manual provenance extraction path', () {
      final raw = jsonDecode(_responseBody('cmp-run-manual'))
          as Map<String, dynamic>;
      _firstProvenanceRun(raw)['extraction_path'] = 'manual';

      final parsed =
          CompetitionAnalyzeResponseWire.parse(jsonEncode(raw));

      expect(parsed.report.competitionId, 'cmp-run-manual');
    });

    test('missing field remains null and has no candidates', () {
      final raw = jsonDecode(_responseBody('cmp-missing'))
          as Map<String, dynamic>;
      final field = _fieldMap(raw, 'registration_deadline');
      field['state'] = 'MISSING';
      field['value'] = null;
      field['normalized_value'] = null;
      field['candidates'] = <Object?>[];
      field['evidence_ids'] = <Object?>[];

      final parsed =
          CompetitionAnalyzeResponseWire.parse(jsonEncode(raw));
      final result =
          parsed.report.canonicalFields['registration_deadline']!;

      expect(result.state, CanonicalFieldState.missing);
      expect(result.value, isNull);
      expect(result.candidates, isEmpty);
    });
  });

  group('2B source identity', () {
    test('same URL and PDF bytes produce stable source identities', () {
      const url = 'https://example.com/rules';
      final bytes = Uint8List.fromList([1, 2, 3, 4]);

      expect(
        SourceIdentity.urlSourceId(url),
        SourceIdentity.urlSourceId(url),
      );
      expect(
        SourceIdentity.pdfSourceId(bytes),
        SourceIdentity.pdfSourceId(bytes),
      );
      expect(
        SourceTypeWire.runtimeOptions,
        isNot(contains(SourceTypeWire.derivedFixture)),
      );
    });


    test('URL and PDF builders preserve exact continuation material', () {
      const source = AnalysisSourceMetadata(
        sourceId: 'src-1',
        sourceType: SourceTypeWire.officialRules,
      );
      const continuation = AnalysisContinuationContext(
        reportBundle: {
          'report': {'competition_id': 'cmp-1'},
          'ref': {'competition_id': 'cmp-1'},
        },
        sourceArtifacts: [
          {'source': {'source_id': 'src-1'}},
        ],
      );

      final urlPayload = buildUrlAnalysisPayload(
        competitionId: 'cmp-1',
        url: 'https://example.com/rules',
        source: source,
        continuation: continuation,
      );
      final pdfPayload = buildPdfAnalysisMetadata(
        competitionId: 'cmp-1',
        documentId: 'pdf:rules.pdf:abc',
        source: source,
        continuation: continuation,
      );

      expect(urlPayload.keys.toSet(), {
        'competition_id',
        'url',
        'source',
        'previous_report_bundle',
        'prior_source_artifacts',
      });
      expect(pdfPayload.keys.toSet(), {
        'competition_id',
        'document_id',
        'source',
        'previous_report_bundle',
        'prior_source_artifacts',
      });
      expect(
        urlPayload['previous_report_bundle'],
        same(continuation.reportBundle),
      );
      expect(
        urlPayload['prior_source_artifacts'],
        same(continuation.sourceArtifacts),
      );
      expect(
        pdfPayload['previous_report_bundle'],
        same(continuation.reportBundle),
      );
      expect(
        pdfPayload['prior_source_artifacts'],
        same(continuation.sourceArtifacts),
      );
    });

    test('source metadata defaults preserve unknown scope/freshness', () {
      const metadata = AnalysisSourceMetadata(
        sourceId: 'src-1',
        sourceType: SourceTypeWire.officialRules,
      );

      expect(metadata.toJson(), {
        'source_id': 'src-1',
        'source_type': 'official_rules',
        'authority_rank': {'basis': 'official_rules'},
        'scope': <String, Object?>{},
        'freshness_metadata': <String, Object?>{},
      });
    });
  });


  group('2B concrete HTTP transport', () {
    test('URL request sends exact contract and preserves original body',
        () async {
      final responseBody = _responseBody('cmp-http-url', pretty: true);
      final recorder = _RecordingHttpClient(responseBody);
      final client = HttpCompetitionApiClient(
        baseUrl: 'https://example.test',
        client: recorder,
      );
      addTearDown(client.close);

      const source = AnalysisSourceMetadata(
        sourceId: 'src-1',
        sourceType: SourceTypeWire.officialRules,
      );
      final result = await client.analyzeUrl(
        competitionId: 'cmp-http-url',
        url: 'https://example.com/rules',
        source: source,
      );

      expect(result.originalBody, responseBody);
      expect(recorder.method, 'POST');
      expect(
        recorder.url?.path,
        '/api/v1/competitions/analyze/url',
      );
      final requestJson =
          jsonDecode(utf8.decode(recorder.bodyBytes!))
              as Map<String, dynamic>;
      expect(requestJson.keys.toSet(), {
        'competition_id',
        'url',
        'source',
        'previous_report_bundle',
        'prior_source_artifacts',
      });
      expect(requestJson['previous_report_bundle'], isNull);
      expect(requestJson['prior_source_artifacts'], isEmpty);
    });


    test('rejects valid JSON response for the wrong competition', () async {
      final recorder = _RecordingHttpClient(
        _responseBody('cmp-other'),
      );
      final client = HttpCompetitionApiClient(
        baseUrl: 'https://example.test',
        client: recorder,
      );
      addTearDown(client.close);

      const source = AnalysisSourceMetadata(
        sourceId: 'src-1',
        sourceType: SourceTypeWire.officialRules,
      );

      await expectLater(
        client.analyzeUrl(
          competitionId: 'cmp-expected',
          url: 'https://example.com/rules',
          source: source,
        ),
        throwsA(
          isA<AnalysisFailure>().having(
            (error) => error.code,
            'code',
            'RESPONSE_CONTRACT_INVALID',
          ),
        ),
      );
    });

    test('PDF multipart contains only metadata and one PDF file', () async {
      final responseBody = _responseBody('cmp-http-pdf');
      final recorder = _RecordingHttpClient(responseBody);
      final client = HttpCompetitionApiClient(
        baseUrl: 'https://example.test',
        client: recorder,
      );
      addTearDown(client.close);

      const source = AnalysisSourceMetadata(
        sourceId: 'src-1',
        sourceType: SourceTypeWire.officialOrganizer,
      );
      final result = await client.analyzePdf(
        competitionId: 'cmp-http-pdf',
        documentId: 'pdf:rules.pdf:abc',
        filename: 'rules.pdf',
        bytes: Uint8List.fromList([37, 80, 68, 70]),
        source: source,
      );

      expect(result.originalBody, responseBody);
      expect(recorder.method, 'POST');
      expect(
        recorder.url?.path,
        '/api/v1/competitions/analyze/pdf',
      );
      expect(recorder.multipartFields.keys.toSet(), {'metadata'});
      expect(recorder.multipartFiles, hasLength(1));
      expect(recorder.multipartFiles.single.field, 'file');
      expect(recorder.multipartFiles.single.filename, 'rules.pdf');
      expect(
        recorder.multipartFiles.single.contentType.toString(),
        'application/pdf',
      );

      final metadata = jsonDecode(
        recorder.multipartFields['metadata']!,
      ) as Map<String, dynamic>;
      expect(metadata.keys.toSet(), {
        'competition_id',
        'document_id',
        'source',
        'previous_report_bundle',
        'prior_source_artifacts',
      });
    });

    test('PDF client rejects wrong media and source over 20 MiB', () async {
      final responseBody = _responseBody('cmp-http-guard');
      final recorder = _RecordingHttpClient(responseBody);
      final client = HttpCompetitionApiClient(
        baseUrl: 'https://example.test',
        client: recorder,
      );
      addTearDown(client.close);

      const source = AnalysisSourceMetadata(
        sourceId: 'src-pdf-guard',
        sourceType: SourceTypeWire.officialRules,
      );

      await expectLater(
        client.analyzePdf(
          competitionId: 'cmp-http-guard',
          documentId: 'doc-image',
          filename: 'image.png',
          bytes: Uint8List.fromList([1]),
          source: source,
        ),
        throwsA(
          isA<AnalysisFailure>().having(
            (error) => error.code,
            'code',
            'CLIENT_MEDIA_TYPE',
          ),
        ),
      );

      await expectLater(
        client.analyzePdf(
          competitionId: 'cmp-http-guard',
          documentId: 'doc-large',
          filename: 'large.pdf',
          bytes: Uint8List(maxAnalysisSourceBytes + 1),
          source: source,
        ),
        throwsA(
          isA<AnalysisFailure>().having(
            (error) => error.code,
            'code',
            'CLIENT_SOURCE_LIMIT',
          ),
        ),
      );

      expect(recorder.calls, 0);
    });


    test('concrete ClientException becomes retryable network failure',
        () async {
      final recorder = _RecordingHttpClient(
        _responseBody('cmp-client-exception'),
        sendError: http.ClientException('offline'),
      );
      final client = HttpCompetitionApiClient(
        baseUrl: 'https://example.test',
        client: recorder,
      );
      addTearDown(client.close);

      const source = AnalysisSourceMetadata(
        sourceId: 'src-1',
        sourceType: SourceTypeWire.officialRules,
      );

      await expectLater(
        client.analyzeUrl(
          competitionId: 'cmp-client-exception',
          url: 'https://example.com/rules',
          source: source,
        ),
        throwsA(
          isA<AnalysisFailure>()
              .having(
                (error) => error.code,
                'code',
                'NETWORK_ERROR',
              )
              .having(
                (error) => error.retryable,
                'retryable',
                isTrue,
              ),
        ),
      );
    });

    test('concrete HTTP timeout becomes retryable network failure',
        () async {
      final recorder = _RecordingHttpClient(
        _responseBody('cmp-timeout'),
        sendDelay: const Duration(milliseconds: 50),
      );
      final client = HttpCompetitionApiClient(
        baseUrl: 'https://example.test',
        client: recorder,
        timeout: const Duration(milliseconds: 5),
      );
      addTearDown(client.close);

      const source = AnalysisSourceMetadata(
        sourceId: 'src-1',
        sourceType: SourceTypeWire.officialRules,
      );

      await expectLater(
        client.analyzeUrl(
          competitionId: 'cmp-timeout',
          url: 'https://example.com/rules',
          source: source,
        ),
        throwsA(
          isA<AnalysisFailure>()
              .having(
                (error) => error.code,
                'code',
                'NETWORK_ERROR',
              )
              .having(
                (error) => error.retryable,
                'retryable',
                isTrue,
              ),
        ),
      );
    });

    test('unknown backend envelope fails safely without invented retry',
        () async {
      final recorder = _RecordingHttpClient(
        '{"detail":"unexpected"}',
        statusCode: 500,
      );
      final client = HttpCompetitionApiClient(
        baseUrl: 'https://example.test',
        client: recorder,
      );
      addTearDown(client.close);

      const source = AnalysisSourceMetadata(
        sourceId: 'src-error',
        sourceType: SourceTypeWire.officialRules,
      );

      await expectLater(
        client.analyzeUrl(
          competitionId: 'cmp-error',
          url: 'https://example.com/rules',
          source: source,
        ),
        throwsA(
          isA<AnalysisFailure>()
              .having(
                (error) => error.code,
                'code',
                'UNKNOWN_BACKEND_ERROR',
              )
              .having(
                (error) => error.retryable,
                'retryable',
                isFalse,
              ),
        ),
      );
    });
  });

  group('2B local persistence', () {
    test('raw HTTP body is stored exactly and snapshots append', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      var tick = 0;
      final repository = DriftAnalysisRepository(
        db,
        now: () => DateTime.utc(
          2026,
          9,
          29,
          12,
          0,
          tick++,
        ),
      );
      addTearDown(repository.close);

      final first = _transport('cmp-persist', pretty: true);
      final second = _transport('cmp-persist', pretty: false);

      await repository.persistResponse(
        originalBody: first.originalBody,
        response: first.response,
      );
      await repository.persistResponse(
        originalBody: second.originalBody,
        response: second.response,
      );

      final snapshots =
          await repository.snapshotsForCompetition('cmp-persist');
      expect(snapshots, hasLength(2));
      expect(snapshots.first.responseJson, first.originalBody);
      expect(snapshots.last.responseJson, second.originalBody);
      expect(
        (await repository.latestSnapshot('cmp-persist'))!.responseJson,
        second.originalBody,
      );
    });

    test('snapshot and competition survive database restart', () async {
      final dir =
          await Directory.systemTemp.createTemp('takt_analysis_restart_');
      final file = File('${dir.path}/takt.sqlite3');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final firstDb = AppDatabase.forTesting(NativeDatabase(file));
      final firstRepository = DriftAnalysisRepository(
        firstDb,
        now: () => DateTime.utc(2026, 9, 29, 12),
      );
      final transport = _transport('cmp-restart', pretty: true);
      await firstRepository.persistResponse(
        originalBody: transport.originalBody,
        response: transport.response,
      );
      await firstRepository.close();

      final secondDb = AppDatabase.forTesting(NativeDatabase(file));
      final secondRepository = DriftAnalysisRepository(secondDb);
      addTearDown(secondRepository.close);

      final restored =
          await secondRepository.latestSnapshot('cmp-restart');
      expect(restored, isNotNull);
      expect(restored!.responseJson, transport.originalBody);

      final competitions = await secondDb.customSelect(
        'SELECT id FROM competitions WHERE id = ?',
        variables: [const Variable<String>('cmp-restart')],
      ).get();
      expect(competitions, hasLength(1));
    });
  });

  group('2B analysis state machine', () {
    test('dispose closes owned analysis resources', () async {
      final api = _FakeApiClient();
      final repository = _MemoryAnalysisRepository();
      final vm = AnalisisViewModel(
        apiClient: api,
        repository: repository,
      );

      vm.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(api.closed, isTrue);
      expect(repository.closed, isTrue);
    });

    test('success persists original body before READY', () async {
      final api = _FakeApiClient();
      final repository = _MemoryAnalysisRepository();
      final vm = AnalisisViewModel(
        apiClient: api,
        repository: repository,
      );

      await vm.analyzeUrl(
        url: 'https://example.com/rules',
        sourceType: SourceTypeWire.officialRules,
        continuation: false,
      );

      expect(vm.phase, AnalysisPhase.ready);
      expect(api.calls, 1);
      expect(repository.persistCalls, 1);
      expect(repository.lastPersistedBody, api.lastBody);
      expect(vm.originalBody, api.lastBody);
    });

    test('persistence retry never repeats backend request', () async {
      final api = _FakeApiClient();
      final repository = _MemoryAnalysisRepository(
        failNextPersist: true,
      );
      final vm = AnalisisViewModel(
        apiClient: api,
        repository: repository,
      );

      await vm.analyzeUrl(
        url: 'https://example.com/rules',
        sourceType: SourceTypeWire.officialRules,
        continuation: false,
      );

      expect(vm.phase, AnalysisPhase.persistenceError);
      expect(vm.canRetryPersistence, isTrue);
      expect(api.calls, 1);
      expect(repository.persistCalls, 1);

      await vm.retryPersistence();

      expect(vm.phase, AnalysisPhase.ready);
      expect(api.calls, 1);
      expect(repository.persistCalls, 2);
    });


    test('broken continuation context requires explicit fresh analysis',
        () async {
      final api = _ContextFailureApiClient();
      final repository = _MemoryAnalysisRepository();
      final vm = AnalisisViewModel(
        apiClient: api,
        repository: repository,
      );

      await vm.analyzeUrl(
        url: 'https://example.com/rules',
        sourceType: SourceTypeWire.officialRules,
        continuation: false,
      );

      expect(vm.phase, AnalysisPhase.requestError);
      expect(vm.requiresFreshAnalysis, isTrue);
      expect(vm.canRetryRequest, isFalse);
    });


    test('corrupt cached continuation requires fresh analysis without API call',
        () async {
      final api = _FakeApiClient();
      final repository = _MemoryAnalysisRepository();
      final vm = AnalisisViewModel(
        apiClient: api,
        repository: repository,
      );

      await vm.analyzeUrl(
        url: 'https://example.com/rules',
        sourceType: SourceTypeWire.officialRules,
        continuation: false,
      );
      expect(vm.phase, AnalysisPhase.ready);
      expect(api.calls, 1);

      repository.corruptLatestOnRead = true;

      await vm.analyzeUrl(
        url: 'https://example.com/faq',
        sourceType: SourceTypeWire.officialFaq,
        continuation: true,
      );

      expect(vm.phase, AnalysisPhase.requestError);
      expect(vm.failure?.code, 'LOCAL_CONTEXT_INVALID');
      expect(vm.requiresFreshAnalysis, isTrue);
      expect(vm.canRetryRequest, isFalse);
      expect(api.calls, 1);
    });

    test('retryable request failure can retry the same request', () async {
      final api = _FakeApiClient(failFirstRequest: true);
      final repository = _MemoryAnalysisRepository();
      final vm = AnalisisViewModel(
        apiClient: api,
        repository: repository,
      );

      await vm.analyzeUrl(
        url: 'https://example.com/rules',
        sourceType: SourceTypeWire.officialRules,
        continuation: false,
      );

      expect(vm.phase, AnalysisPhase.requestError);
      expect(vm.canRetryRequest, isTrue);
      expect(api.calls, 1);
      expect(repository.persistCalls, 0);

      await vm.retryRequest();

      expect(vm.phase, AnalysisPhase.ready);
      expect(api.calls, 2);
      expect(repository.persistCalls, 1);
    });


    test('double submit is ignored while request is in flight', () async {
      final api = _BlockingApiClient();
      final repository = _MemoryAnalysisRepository();
      final vm = AnalisisViewModel(
        apiClient: api,
        repository: repository,
      );

      final first = vm.analyzeUrl(
        url: 'https://example.com/rules',
        sourceType: SourceTypeWire.officialRules,
        continuation: false,
      );
      await Future<void>.delayed(Duration.zero);

      await vm.analyzeUrl(
        url: 'https://example.com/faq',
        sourceType: SourceTypeWire.officialFaq,
        continuation: false,
      );

      expect(api.calls, 1);
      api.complete();
      await first;

      expect(vm.phase, AnalysisPhase.ready);
      expect(repository.persistCalls, 1);
    });

    test('add-source continuation reuses competition and exact cache context',
        () async {
      final api = _FakeApiClient();
      final repository = _MemoryAnalysisRepository();
      final vm = AnalisisViewModel(
        apiClient: api,
        repository: repository,
      );

      await vm.analyzeUrl(
        url: 'https://example.com/rules',
        sourceType: SourceTypeWire.officialRules,
        continuation: false,
      );
      final firstCompetition = vm.competitionId!;
      final cachedBody = repository.lastPersistedBody!;
      final cachedRaw =
          decodeOriginalResponseMap(cachedBody);

      await vm.analyzeUrl(
        url: 'https://example.com/faq',
        sourceType: SourceTypeWire.officialFaq,
        continuation: true,
      );

      expect(api.competitionIds, [firstCompetition, firstCompetition]);
      expect(
        api.lastContinuation!.reportBundle,
        cachedRaw['report_bundle'],
      );
      expect(
        api.lastContinuation!.sourceArtifacts,
        cachedRaw['source_artifacts'],
      );
    });
  });
}



Map<String, dynamic> _firstProvenanceRun(
  Map<String, dynamic> raw,
) {
  final provenance = raw['provenance'] as Map<String, dynamic>;
  final runs = provenance['extraction_runs'] as List<dynamic>;
  return runs.first as Map<String, dynamic>;
}

Map<String, dynamic> _firstSourceArtifact(
  Map<String, dynamic> raw,
) {
  final artifacts = raw['source_artifacts'] as List<dynamic>;
  return artifacts.first as Map<String, dynamic>;
}

Map<String, dynamic> _firstCandidateReport(
  Map<String, dynamic> raw,
) {
  final artifact = _firstSourceArtifact(raw);
  final reports = artifact['candidate_reports'] as List<dynamic>;
  return reports.first as Map<String, dynamic>;
}

Map<String, Object?> _reportCandidateField({
  required String fieldName,
  required List<String> evidenceIds,
  String extractionPath = 'native',
}) {
  return {
    'field_name': fieldName,
    'raw_value': '$fieldName raw',
    'normalized_value': '$fieldName normalized',
    'evidence_ids': evidenceIds,
    'extraction_path': extractionPath,
    'confidence': null,
    'scope': <String, Object?>{},
  };
}

Map<String, Object?> _reportEvidence({
  required String evidenceId,
  required String fieldName,
  String extractionPath = 'native',
}) {
  return {
    'evidence_id': evidenceId,
    'source_id': 'src-1',
    'page_or_locator': 'section:$fieldName',
    'raw_text_or_visual_reference': '$fieldName evidence',
    'field_name': fieldName,
    'extraction_path': extractionPath,
    'extractor_version': 'test-v1',
  };
}

Map<String, dynamic> _fieldMap(
  Map<String, dynamic> raw,
  String name,
) {
  final bundle = raw['report_bundle'] as Map<String, dynamic>;
  final report = bundle['report'] as Map<String, dynamic>;
  final fields = report['canonical_fields'] as Map<String, dynamic>;
  return fields[name] as Map<String, dynamic>;
}

Map<String, Object?> _candidate(
  String fieldName,
  Object value,
  String evidenceId,
) {
  return {
    'field_name': fieldName,
    'raw_value': value,
    'normalized_value': value,
    'evidence_ids': [evidenceId],
    'extraction_path': 'native',
    'confidence': null,
    'scope': <String, Object?>{},
  };
}

String _responseBody(
  String competitionId, {
  bool pretty = false,
}) {
  const sourceId = 'src-1';
  final fields = <String, Object?>{};
  final evidence = <Object?>[];

  for (final name in coreCanonicalFieldNames) {
    final evidenceId = 'ev-$name';
    final value = '$name-value';
    fields[name] = {
      'field_name': name,
      'state': 'VERIFIED',
      'value': value,
      'normalized_value': value,
      'candidates': [
        _candidate(name, value, evidenceId),
      ],
      'evidence_ids': [evidenceId],
    };
    evidence.add({
      'evidence_id': evidenceId,
      'source_id': sourceId,
      'page_or_locator': 'section:$name',
      'raw_text_or_visual_reference': '$name raw evidence',
      'field_name': name,
      'extraction_path': 'native',
      'extractor_version': 'test-v1',
    });
  }

  final source = {
    'source_id': sourceId,
    'source_type': 'official_rules',
    'url_or_document_id': 'https://example.com/rules',
    'retrieved_at': '2026-09-29T05:00:00Z',
    'content_hash': 'sha256:test',
    'authority_rank': {'basis': 'official_rules'},
    'scope': <String, Object?>{},
    'freshness_metadata': <String, Object?>{},
  };

  final payload = {
    'report_bundle': {
      'report': {
        'competition_id': competitionId,
        'report_version': 1,
        'source_ids': [sourceId],
        'canonical_fields': fields,
        'unresolved_critical_fields': <String>[],
      },
      'ref': {
        'domain_schema_version': '3.0.0',
        'competition_id': competitionId,
        'report_version': 1,
        'reconciliation_policy_version': 'reconciliation-v1',
        'assembly_policy_version': 'canonical-v1',
        'assembly_material_fingerprint': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'source_set_fingerprint_version': 'source-set-jcs-sha256-v1',
        'source_set_fingerprint': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        'wire_fingerprint_version': 'report-wire-jcs-sha256-v1',
        'wire_fingerprint': 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      },
    },
    'source_artifacts': [
      {
        'source': source,
        'candidate_reports': [
          {
            'source_id': sourceId,
            'extraction_path': 'native',
            'fields': <Object?>[],
            'evidence': <Object?>[],
          },
        ],
        'extraction_runs': [
          {
            'source_id': sourceId,
            'snapshot_id': 'snap-1',
            'extraction_path': 'native',
            'extractor_version': 'test-v1',
          },
        ],
      },
    ],
    'provenance': {
      'sources': [source],
      'extraction_runs': [
        {
          'source_id': sourceId,
          'snapshot_id': 'snap-1',
          'extraction_path': 'native',
          'extractor_version': 'test-v1',
        },
      ],
      'evidence': evidence,
    },
    'report_changed': true,
  };

  return pretty
      ? const JsonEncoder.withIndent('  ').convert(payload)
      : jsonEncode(payload);
}

CompetitionAnalysisTransportResult _transport(
  String competitionId, {
  bool pretty = false,
}) {
  final body = _responseBody(
    competitionId,
    pretty: pretty,
  );
  return CompetitionAnalysisTransportResult(
    originalBody: body,
    response: CompetitionAnalyzeResponseWire.parse(body),
  );
}


class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient(
    this.responseBody, {
    this.statusCode = 200,
    this.sendError,
    this.sendDelay,
  });

  final String responseBody;
  final int statusCode;
  final Object? sendError;
  final Duration? sendDelay;
  int calls = 0;
  String? method;
  Uri? url;
  Uint8List? bodyBytes;
  Map<String, String> multipartFields = {};
  List<http.MultipartFile> multipartFiles = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls += 1;
    final delay = sendDelay;
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    final error = sendError;
    if (error != null) {
      throw error;
    }
    method = request.method;
    url = request.url;
    if (request is http.MultipartRequest) {
      multipartFields = Map<String, String>.from(request.fields);
      multipartFiles = List<http.MultipartFile>.from(request.files);
    }
    bodyBytes = Uint8List.fromList(
      await request.finalize().toBytes(),
    );
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(responseBody)),
      statusCode,
      headers: const {'content-type': 'application/json'},
    );
  }
}


class _BlockingApiClient implements CompetitionApiClient {
  final Completer<CompetitionAnalysisTransportResult> _completer =
      Completer<CompetitionAnalysisTransportResult>();
  int calls = 0;
  String? competitionId;

  @override
  Future<CompetitionAnalysisTransportResult> analyzeUrl({
    required String competitionId,
    required String url,
    required AnalysisSourceMetadata source,
    AnalysisContinuationContext? continuation,
  }) {
    calls += 1;
    this.competitionId = competitionId;
    return _completer.future;
  }

  void complete() {
    final id = competitionId;
    if (id == null) throw StateError('request has not started');
    _completer.complete(_transport(id, pretty: true));
  }

  @override
  Future<CompetitionAnalysisTransportResult> analyzePdf({
    required String competitionId,
    required String documentId,
    required String filename,
    required Uint8List bytes,
    required AnalysisSourceMetadata source,
    AnalysisContinuationContext? continuation,
  }) {
    return analyzeUrl(
      competitionId: competitionId,
      url: documentId,
      source: source,
      continuation: continuation,
    );
  }

  @override
  void close() {}
}

class _FakeApiClient implements CompetitionApiClient {
  _FakeApiClient({this.failFirstRequest = false});

  final bool failFirstRequest;
  int calls = 0;
  bool closed = false;
  String? lastBody;
  AnalysisContinuationContext? lastContinuation;
  final List<String> competitionIds = [];

  @override
  Future<CompetitionAnalysisTransportResult> analyzeUrl({
    required String competitionId,
    required String url,
    required AnalysisSourceMetadata source,
    AnalysisContinuationContext? continuation,
  }) async {
    calls += 1;
    competitionIds.add(competitionId);
    lastContinuation = continuation;
    if (failFirstRequest && calls == 1) {
      throw const AnalysisFailure(
        code: 'SOURCE_FETCH_FAILED',
        stage: 'ingestion',
        message: 'simulated',
        userMessage: 'simulated',
        retryable: true,
      );
    }
    final result = _transport(competitionId, pretty: true);
    lastBody = result.originalBody;
    return result;
  }

  @override
  Future<CompetitionAnalysisTransportResult> analyzePdf({
    required String competitionId,
    required String documentId,
    required String filename,
    required Uint8List bytes,
    required AnalysisSourceMetadata source,
    AnalysisContinuationContext? continuation,
  }) {
    return analyzeUrl(
      competitionId: competitionId,
      url: documentId,
      source: source,
      continuation: continuation,
    );
  }

  @override
  void close() {
    closed = true;
  }
}


class _ContextFailureApiClient implements CompetitionApiClient {
  @override
  Future<CompetitionAnalysisTransportResult> analyzeUrl({
    required String competitionId,
    required String url,
    required AnalysisSourceMetadata source,
    AnalysisContinuationContext? continuation,
  }) async {
    throw const AnalysisFailure(
      code: 'ANALYSIS_CONTEXT_INVALID',
      stage: 'analysis',
      message: 'simulated context mismatch',
      userMessage: 'simulated context mismatch',
      retryable: false,
    );
  }

  @override
  Future<CompetitionAnalysisTransportResult> analyzePdf({
    required String competitionId,
    required String documentId,
    required String filename,
    required Uint8List bytes,
    required AnalysisSourceMetadata source,
    AnalysisContinuationContext? continuation,
  }) {
    return analyzeUrl(
      competitionId: competitionId,
      url: documentId,
      source: source,
      continuation: continuation,
    );
  }

  @override
  void close() {}
}

class _MemoryAnalysisRepository implements AnalysisRepository {
  _MemoryAnalysisRepository({
    this.failNextPersist = false,
  });

  bool failNextPersist;
  bool corruptLatestOnRead = false;
  int persistCalls = 0;
  bool closed = false;
  String? lastPersistedBody;
  final List<AnalysisSnapshot> _snapshots = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<AnalysisSnapshot?> latestSnapshot(
    String competitionId,
  ) async {
    final matches = _snapshots
        .where((item) => item.competitionId == competitionId)
        .toList();
    if (matches.isEmpty) return null;

    final latest = matches.last;
    if (!corruptLatestOnRead) return latest;

    return AnalysisSnapshot(
      id: latest.id,
      competitionId: latest.competitionId,
      reportVersion: latest.reportVersion,
      assemblyMaterialFingerprint:
          latest.assemblyMaterialFingerprint,
      sourceSetFingerprint: latest.sourceSetFingerprint,
      wireFingerprint: latest.wireFingerprint,
      reportChanged: latest.reportChanged,
      responseJson: '{"broken":',
      cachedAtEpochMs: latest.cachedAtEpochMs,
    );
  }

  @override
  Future<List<AnalysisSnapshot>> snapshotsForCompetition(
    String competitionId,
  ) async {
    return _snapshots
        .where((item) => item.competitionId == competitionId)
        .toList(growable: false);
  }

  @override
  Future<AnalysisSnapshot> persistResponse({
    required String originalBody,
    required CompetitionAnalyzeResponseWire response,
  }) async {
    persistCalls += 1;
    if (failNextPersist) {
      failNextPersist = false;
      throw StateError('simulated persistence failure');
    }
    lastPersistedBody = originalBody;
    final snapshot = AnalysisSnapshot(
      id: 'snapshot-$persistCalls',
      competitionId: response.report.competitionId,
      reportVersion: response.report.reportVersion,
      assemblyMaterialFingerprint:
          response.ref.assemblyMaterialFingerprint,
      sourceSetFingerprint: response.ref.sourceSetFingerprint,
      wireFingerprint: response.ref.wireFingerprint,
      reportChanged: response.reportChanged,
      responseJson: originalBody,
      cachedAtEpochMs: persistCalls,
    );
    _snapshots.add(snapshot);
    return snapshot;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
