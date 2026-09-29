import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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
  });

  group('2B analysis state machine', () {
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

      await vm.retryRequest();

      expect(vm.phase, AnalysisPhase.ready);
      expect(api.calls, 2);
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

class _FakeApiClient implements CompetitionApiClient {
  _FakeApiClient({this.failFirstRequest = false});

  final bool failFirstRequest;
  int calls = 0;
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
}

class _MemoryAnalysisRepository implements AnalysisRepository {
  _MemoryAnalysisRepository({this.failNextPersist = false});

  bool failNextPersist;
  int persistCalls = 0;
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
    return matches.isEmpty ? null : matches.last;
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
  Future<void> close() async {}
}
