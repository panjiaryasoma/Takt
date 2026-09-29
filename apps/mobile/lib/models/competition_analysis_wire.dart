import 'dart:convert';

const supportedDomainSchemaVersion = '3.0.0';
const supportedReconciliationPolicyVersion = 'reconciliation-v1';
const supportedAssemblyPolicyVersion = 'canonical-v1';
const supportedSourceSetFingerprintVersion = 'source-set-jcs-sha256-v1';
const supportedWireFingerprintVersion = 'report-wire-jcs-sha256-v1';

const coreCanonicalFieldNames = <String>{
  'competition_name',
  'organizer',
  'submission_deadline',
  'registration_deadline',
  'eligibility',
  'team_size',
  'format',
  'location',
  'tracks_or_categories',
  'deliverables',
  'required_technologies',
  'judging_criteria',
  'prizes_or_benefits',
};

enum CanonicalFieldState {
  verified('VERIFIED'),
  singleSource('SINGLE_SOURCE'),
  conflict('CONFLICT'),
  missing('MISSING'),
  unverified('UNVERIFIED');

  const CanonicalFieldState(this.wire);
  final String wire;

  static CanonicalFieldState fromWire(String value) {
    return CanonicalFieldState.values.firstWhere(
      (item) => item.wire == value,
      orElse: () => throw FormatException(
        'Unknown canonical field state: $value',
      ),
    );
  }
}

enum SourceTypeWire {
  officialRules('official_rules'),
  officialOrganizer('official_organizer'),
  officialFaq('official_faq'),
  platform('platform'),
  secondary('secondary'),
  derivedFixture('derived_fixture');

  const SourceTypeWire(this.wire);
  final String wire;

  static const runtimeOptions = <SourceTypeWire>[
    officialRules,
    officialOrganizer,
    officialFaq,
    platform,
    secondary,
  ];

  static SourceTypeWire fromWire(String value) {
    return SourceTypeWire.values.firstWhere(
      (item) => item.wire == value,
      orElse: () => throw FormatException('Unknown source type: $value'),
    );
  }
}

class CandidateFieldWire {
  const CandidateFieldWire({
    required this.rawValue,
    required this.normalizedValue,
    required this.evidenceIds,
  });

  final Object? rawValue;
  final Object? normalizedValue;
  final List<String> evidenceIds;

  factory CandidateFieldWire.fromJson(
    Object? value, {
    required String fieldName,
    required String path,
  }) {
    final map = _object(value, path);
    _expectKeys(
      map,
      const {
        'field_name',
        'raw_value',
        'normalized_value',
        'evidence_ids',
        'extraction_path',
        'confidence',
        'scope',
      },
      path,
    );
    if (_string(map['field_name'], '$path.field_name') != fieldName) {
      throw FormatException('$path field_name mismatch');
    }
    final extractionPath =
        _string(map['extraction_path'], '$path.extraction_path');
    if (!const {'native', 'ocr', 'vision'}.contains(extractionPath)) {
      throw FormatException('$path has unsupported extraction path');
    }
    final confidence = map['confidence'];
    if (confidence != null &&
        (confidence is! num || confidence < 0 || confidence > 1)) {
      throw FormatException('$path.confidence must be 0..1 or null');
    }
    if (map['scope'] == null) {
      throw FormatException('$path.scope must be explicit');
    }
    return CandidateFieldWire(
      rawValue: map['raw_value'],
      normalizedValue: map['normalized_value'],
      evidenceIds: _strings(map['evidence_ids'], '$path.evidence_ids'),
    );
  }
}

class CanonicalFieldWire {
  const CanonicalFieldWire({
    required this.fieldName,
    required this.state,
    required this.value,
    required this.normalizedValue,
    required this.candidates,
    required this.evidenceIds,
  });

  final String fieldName;
  final CanonicalFieldState state;
  final Object? value;
  final Object? normalizedValue;
  final List<CandidateFieldWire> candidates;
  final List<String> evidenceIds;

  factory CanonicalFieldWire.fromJson(
    Object? value, {
    required String mapKey,
  }) {
    final path = 'report.canonical_fields.$mapKey';
    final map = _object(value, path);
    _expectKeys(
      map,
      const {
        'field_name',
        'state',
        'value',
        'normalized_value',
        'candidates',
        'evidence_ids',
      },
      path,
    );
    final fieldName = _string(map['field_name'], '$path.field_name');
    if (fieldName != mapKey) {
      throw FormatException('$path key must match field_name');
    }
    final candidates = _list(map['candidates'], '$path.candidates')
        .asMap()
        .entries
        .map(
          (entry) => CandidateFieldWire.fromJson(
            entry.value,
            fieldName: fieldName,
            path: '$path.candidates[${entry.key}]',
          ),
        )
        .toList(growable: false);
    final result = CanonicalFieldWire(
      fieldName: fieldName,
      state: CanonicalFieldState.fromWire(
        _string(map['state'], '$path.state'),
      ),
      value: map['value'],
      normalizedValue: map['normalized_value'],
      candidates: candidates,
      evidenceIds: _strings(map['evidence_ids'], '$path.evidence_ids'),
    );
    final candidateEvidence = <String>{
      for (final candidate in candidates) ...candidate.evidenceIds,
    };
    if (!result.evidenceIds.toSet().containsAll(candidateEvidence)) {
      throw FormatException(
        '$path canonical evidence must retain candidate evidence',
      );
    }
    result._validate(path);
    return result;
  }

  void _validate(String path) {
    switch (state) {
      case CanonicalFieldState.verified:
      case CanonicalFieldState.singleSource:
        if (value == null || normalizedValue == null) {
          throw FormatException('$path ${state.wire} requires a usable value');
        }
        if (candidates.isEmpty || evidenceIds.isEmpty) {
          throw FormatException('$path ${state.wire} requires provenance');
        }
        return;
      case CanonicalFieldState.conflict:
        if (value != null || normalizedValue != null) {
          throw FormatException('$path CONFLICT must not expose a value');
        }
        if (candidates.length < 2 || evidenceIds.length < 2) {
          throw FormatException('$path CONFLICT requires multiple evidence');
        }
        final normalizedCandidates = candidates
            .map((candidate) => _stableJson(candidate.normalizedValue))
            .toSet();
        if (normalizedCandidates.length < 2) {
          throw FormatException(
            '$path CONFLICT requires normalized candidate disagreement',
          );
        }
        return;
      case CanonicalFieldState.missing:
        if (value != null ||
            normalizedValue != null ||
            candidates.isNotEmpty) {
          throw FormatException('$path MISSING must not invent a value');
        }
        return;
      case CanonicalFieldState.unverified:
        if (value != null || normalizedValue != null) {
          throw FormatException('$path UNVERIFIED must not expose a value');
        }
        if (candidates.isEmpty || evidenceIds.isEmpty) {
          throw FormatException('$path UNVERIFIED requires provenance');
        }
        return;
    }
  }
}

class CanonicalCompetitionReportWire {
  const CanonicalCompetitionReportWire({
    required this.competitionId,
    required this.reportVersion,
    required this.sourceIds,
    required this.canonicalFields,
    required this.unresolvedCriticalFields,
  });

  final String competitionId;
  final int reportVersion;
  final List<String> sourceIds;
  final Map<String, CanonicalFieldWire> canonicalFields;
  final List<String> unresolvedCriticalFields;

  factory CanonicalCompetitionReportWire.fromJson(Object? value) {
    final map = _object(value, 'report');
    _expectKeys(
      map,
      const {
        'competition_id',
        'report_version',
        'source_ids',
        'canonical_fields',
        'unresolved_critical_fields',
      },
      'report',
    );
    final reportVersion =
        _integer(map['report_version'], 'report.report_version');
    if (reportVersion < 1) {
      throw const FormatException('report_version must be >= 1');
    }

    final rawFields =
        _object(map['canonical_fields'], 'report.canonical_fields');
    final fields = <String, CanonicalFieldWire>{};
    for (final entry in rawFields.entries) {
      fields[entry.key] = CanonicalFieldWire.fromJson(
        entry.value,
        mapKey: entry.key,
      );
    }
    final missing =
        coreCanonicalFieldNames.difference(fields.keys.toSet());
    if (missing.isNotEmpty) {
      throw FormatException(
        'Canonical report missing core fields: ${missing.join(', ')}',
      );
    }

    final unresolved = _strings(
      map['unresolved_critical_fields'],
      'report.unresolved_critical_fields',
    );
    for (final name in unresolved) {
      final field = fields[name];
      if (field == null ||
          !const {
            CanonicalFieldState.conflict,
            CanonicalFieldState.missing,
            CanonicalFieldState.unverified,
          }.contains(field.state)) {
        throw const FormatException(
          'unresolved_critical_fields references a resolved field',
        );
      }
    }

    return CanonicalCompetitionReportWire(
      competitionId:
          _string(map['competition_id'], 'report.competition_id'),
      reportVersion: reportVersion,
      sourceIds: _strings(map['source_ids'], 'report.source_ids'),
      canonicalFields: Map.unmodifiable(fields),
      unresolvedCriticalFields: unresolved,
    );
  }
}

class CanonicalReportRefWire {
  const CanonicalReportRefWire({
    required this.competitionId,
    required this.reportVersion,
    required this.assemblyMaterialFingerprint,
    required this.sourceSetFingerprint,
    required this.wireFingerprint,
  });

  final String competitionId;
  final int reportVersion;
  final String assemblyMaterialFingerprint;
  final String? sourceSetFingerprint;
  final String wireFingerprint;

  factory CanonicalReportRefWire.fromJson(Object? value) {
    final map = _object(value, 'report_ref');
    _expectKeys(
      map,
      const {
        'domain_schema_version',
        'competition_id',
        'report_version',
        'reconciliation_policy_version',
        'assembly_policy_version',
        'assembly_material_fingerprint',
        'source_set_fingerprint_version',
        'source_set_fingerprint',
        'wire_fingerprint_version',
        'wire_fingerprint',
      },
      'report_ref',
    );
    final supportedVersions = <String, String>{
      'domain_schema_version': supportedDomainSchemaVersion,
      'reconciliation_policy_version':
          supportedReconciliationPolicyVersion,
      'assembly_policy_version': supportedAssemblyPolicyVersion,
      'source_set_fingerprint_version':
          supportedSourceSetFingerprintVersion,
      'wire_fingerprint_version': supportedWireFingerprintVersion,
    };
    for (final entry in supportedVersions.entries) {
      final actual =
          _string(map[entry.key], 'report_ref.${entry.key}');
      if (actual != entry.value) {
        throw FormatException(
          'Unsupported report contract version ${entry.key}: $actual',
        );
      }
    }

    final sourceSet = map['source_set_fingerprint'];
    return CanonicalReportRefWire(
      competitionId:
          _string(map['competition_id'], 'report_ref.competition_id'),
      reportVersion:
          _integer(map['report_version'], 'report_ref.report_version'),
      assemblyMaterialFingerprint: _sha256(
        _string(
          map['assembly_material_fingerprint'],
          'report_ref.assembly_material_fingerprint',
        ),
        'report_ref.assembly_material_fingerprint',
      ),
      sourceSetFingerprint: sourceSet == null
          ? null
          : _sha256(
              _string(sourceSet, 'report_ref.source_set_fingerprint'),
              'report_ref.source_set_fingerprint',
            ),
      wireFingerprint: _sha256(
        _string(
          map['wire_fingerprint'],
          'report_ref.wire_fingerprint',
        ),
        'report_ref.wire_fingerprint',
      ),
    );
  }
}

class SourceRecordWire {
  const SourceRecordWire({
    required this.sourceId,
    required this.sourceType,
    required this.urlOrDocumentId,
    required this.retrievedAt,
  });

  final String sourceId;
  final SourceTypeWire sourceType;
  final String urlOrDocumentId;
  final String retrievedAt;

  factory SourceRecordWire.fromJson(
    Object? value, {
    required String path,
  }) {
    final map = _object(value, path);
    _expectKeys(
      map,
      const {
        'source_id',
        'source_type',
        'url_or_document_id',
        'retrieved_at',
        'content_hash',
        'authority_rank',
        'scope',
        'freshness_metadata',
      },
      path,
    );
    final retrievedAt =
        _string(map['retrieved_at'], '$path.retrieved_at');
    final aware = RegExp(r'(Z|[+-]\d{2}:\d{2})$');
    if (DateTime.tryParse(retrievedAt) == null ||
        !aware.hasMatch(retrievedAt)) {
      throw FormatException('$path.retrieved_at must be timezone-aware');
    }
    if (map['authority_rank'] == null ||
        map['scope'] == null ||
        map['freshness_metadata'] == null) {
      throw FormatException('$path source metadata must be explicit');
    }
    return SourceRecordWire(
      sourceId: _string(map['source_id'], '$path.source_id'),
      sourceType: SourceTypeWire.fromWire(
        _string(map['source_type'], '$path.source_type'),
      ),
      urlOrDocumentId: _string(
        map['url_or_document_id'],
        '$path.url_or_document_id',
      ),
      retrievedAt: retrievedAt,
    );
  }
}

class EvidenceSpanWire {
  const EvidenceSpanWire({
    required this.evidenceId,
    required this.sourceId,
    required this.pageOrLocator,
    required this.rawReference,
    required this.fieldName,
    required this.extractionPath,
  });

  final String evidenceId;
  final String sourceId;
  final Object pageOrLocator;
  final Object rawReference;
  final String fieldName;
  final String extractionPath;

  factory EvidenceSpanWire.fromJson(
    Object? value, {
    required String path,
  }) {
    final map = _object(value, path);
    _expectKeys(
      map,
      const {
        'evidence_id',
        'source_id',
        'page_or_locator',
        'raw_text_or_visual_reference',
        'field_name',
        'extraction_path',
        'extractor_version',
      },
      path,
    );
    if (map['page_or_locator'] == null ||
        map['raw_text_or_visual_reference'] == null) {
      throw FormatException('$path evidence locator must be explicit');
    }
    final extractionPath =
        _string(map['extraction_path'], '$path.extraction_path');
    if (!const {'native', 'ocr', 'vision', 'manual'}
        .contains(extractionPath)) {
      throw FormatException('$path has unsupported extraction path');
    }
    _string(map['extractor_version'], '$path.extractor_version');
    return EvidenceSpanWire(
      evidenceId:
          _string(map['evidence_id'], '$path.evidence_id'),
      sourceId: _string(map['source_id'], '$path.source_id'),
      pageOrLocator: map['page_or_locator']!,
      rawReference: map['raw_text_or_visual_reference']!,
      fieldName: _string(map['field_name'], '$path.field_name'),
      extractionPath: extractionPath,
    );
  }
}

class AnalysisProvenanceWire {
  const AnalysisProvenanceWire({
    required this.sources,
    required this.evidence,
  });

  final List<SourceRecordWire> sources;
  final List<EvidenceSpanWire> evidence;

  factory AnalysisProvenanceWire.fromJson(Object? value) {
    final map = _object(value, 'provenance');
    _expectKeys(
      map,
      const {'sources', 'extraction_runs', 'evidence'},
      'provenance',
    );
    final sources = _list(map['sources'], 'provenance.sources')
        .asMap()
        .entries
        .map(
          (entry) => SourceRecordWire.fromJson(
            entry.value,
            path: 'provenance.sources[${entry.key}]',
          ),
        )
        .toList(growable: false);
    final evidence = _list(map['evidence'], 'provenance.evidence')
        .asMap()
        .entries
        .map(
          (entry) => EvidenceSpanWire.fromJson(
            entry.value,
            path: 'provenance.evidence[${entry.key}]',
          ),
        )
        .toList(growable: false);

    for (final entry
        in _list(map['extraction_runs'], 'provenance.extraction_runs')
            .asMap()
            .entries) {
      final run = _object(
        entry.value,
        'provenance.extraction_runs[${entry.key}]',
      );
      _expectKeys(
        run,
        const {
          'source_id',
          'snapshot_id',
          'extraction_path',
          'extractor_version',
        },
        'provenance.extraction_runs[${entry.key}]',
      );
    }

    return AnalysisProvenanceWire(
      sources: sources,
      evidence: evidence,
    );
  }

  SourceRecordWire? sourceById(String sourceId) {
    for (final source in sources) {
      if (source.sourceId == sourceId) return source;
    }
    return null;
  }

  EvidenceSpanWire? evidenceById(String evidenceId) {
    for (final item in evidence) {
      if (item.evidenceId == evidenceId) return item;
    }
    return null;
  }
}

class CompetitionAnalyzeResponseWire {
  const CompetitionAnalyzeResponseWire({
    required this.report,
    required this.ref,
    required this.provenance,
    required this.reportChanged,
  });

  final CanonicalCompetitionReportWire report;
  final CanonicalReportRefWire ref;
  final AnalysisProvenanceWire provenance;
  final bool reportChanged;

  factory CompetitionAnalyzeResponseWire.parse(String originalBody) {
    final root = decodeOriginalResponseMap(originalBody);
    _expectKeys(
      root,
      const {
        'report_bundle',
        'source_artifacts',
        'provenance',
        'report_changed',
      },
      'response',
    );

    final bundle = _object(root['report_bundle'], 'report_bundle');
    _expectKeys(bundle, const {'report', 'ref'}, 'report_bundle');
    final report =
        CanonicalCompetitionReportWire.fromJson(bundle['report']);
    final ref = CanonicalReportRefWire.fromJson(bundle['ref']);
    if (report.competitionId != ref.competitionId ||
        report.reportVersion != ref.reportVersion) {
      throw const FormatException('report/ref identity mismatch');
    }

    final artifactIds = <String>{};
    for (final entry
        in _list(root['source_artifacts'], 'source_artifacts')
            .asMap()
            .entries) {
      final path = 'source_artifacts[${entry.key}]';
      final artifact = _object(entry.value, path);
      _expectKeys(
        artifact,
        const {'source', 'candidate_reports', 'extraction_runs'},
        path,
      );
      final source = SourceRecordWire.fromJson(
        artifact['source'],
        path: '$path.source',
      );
      if (!artifactIds.add(source.sourceId)) {
        throw const FormatException('Duplicate source artifact ID');
      }

      final reports = _list(
        artifact['candidate_reports'],
        '$path.candidate_reports',
      );
      if (reports.isEmpty) {
        throw const FormatException(
          'Source artifact must keep candidate reports',
        );
      }
      for (final reportEntry in reports.asMap().entries) {
        final reportPath =
            '$path.candidate_reports[${reportEntry.key}]';
        final report = _object(reportEntry.value, reportPath);
        _expectKeys(
          report,
          const {'source_id', 'extraction_path', 'fields', 'evidence'},
          reportPath,
        );
        if (_string(report['source_id'], '$reportPath.source_id') !=
            source.sourceId) {
          throw FormatException('$reportPath source_id mismatch');
        }
        final extractionPath = _string(
          report['extraction_path'],
          '$reportPath.extraction_path',
        );
        if (!const {'native', 'ocr', 'vision'}
            .contains(extractionPath)) {
          throw FormatException(
            '$reportPath has unsupported extraction path',
          );
        }
        for (final fieldEntry
            in _list(report['fields'], '$reportPath.fields')
                .asMap()
                .entries) {
          final fieldMap = _object(
            fieldEntry.value,
            '$reportPath.fields[${fieldEntry.key}]',
          );
          final fieldName = _string(
            fieldMap['field_name'],
            '$reportPath.fields[${fieldEntry.key}].field_name',
          );
          CandidateFieldWire.fromJson(
            fieldMap,
            fieldName: fieldName,
            path: '$reportPath.fields[${fieldEntry.key}]',
          );
        }
        for (final evidenceEntry
            in _list(report['evidence'], '$reportPath.evidence')
                .asMap()
                .entries) {
          final evidence = EvidenceSpanWire.fromJson(
            evidenceEntry.value,
            path:
                '$reportPath.evidence[${evidenceEntry.key}]',
          );
          if (evidence.sourceId != source.sourceId ||
              evidence.extractionPath != extractionPath) {
            throw FormatException(
              '$reportPath evidence continuity mismatch',
            );
          }
        }
      }

      final runs = _list(
        artifact['extraction_runs'],
        '$path.extraction_runs',
      );
      if (runs.isEmpty) {
        throw const FormatException(
          'Source artifact must keep extraction runs',
        );
      }
      for (final runEntry in runs.asMap().entries) {
        final runPath = '$path.extraction_runs[${runEntry.key}]';
        final run = _object(runEntry.value, runPath);
        _expectKeys(
          run,
          const {
            'source_id',
            'snapshot_id',
            'extraction_path',
            'extractor_version',
          },
          runPath,
        );
        if (_string(run['source_id'], '$runPath.source_id') !=
            source.sourceId) {
          throw FormatException('$runPath source_id mismatch');
        }
        _string(run['snapshot_id'], '$runPath.snapshot_id');
        _string(run['extractor_version'], '$runPath.extractor_version');
        final pathValue = _string(
          run['extraction_path'],
          '$runPath.extraction_path',
        );
        if (!const {'native', 'ocr', 'vision'}.contains(pathValue)) {
          throw FormatException(
            '$runPath has unsupported extraction path',
          );
        }
      }
    }

    final provenance =
        AnalysisProvenanceWire.fromJson(root['provenance']);
    final reportIds = report.sourceIds.toSet();
    final provenanceIds =
        provenance.sources.map((item) => item.sourceId).toSet();
    if (!_sameSet(artifactIds, reportIds) ||
        !_sameSet(artifactIds, provenanceIds)) {
      throw const FormatException('Source-set traceability mismatch');
    }

    final availableEvidence =
        provenance.evidence.map((item) => item.evidenceId).toSet();
    final referencedEvidence = <String>{
      for (final field in report.canonicalFields.values)
        ...field.evidenceIds,
    };
    if (!availableEvidence.containsAll(referencedEvidence)) {
      throw const FormatException(
        'Canonical evidence does not resolve in provenance',
      );
    }

    final changed = root['report_changed'];
    if (changed is! bool) {
      throw const FormatException('report_changed must be boolean');
    }
    return CompetitionAnalyzeResponseWire(
      report: report,
      ref: ref,
      provenance: provenance,
      reportChanged: changed,
    );
  }
}

Map<String, dynamic> decodeOriginalResponseMap(String originalBody) {
  final decoded = jsonDecode(originalBody);
  return _object(decoded, 'response');
}

Map<String, dynamic> _object(Object? value, String path) {
  if (value is! Map) {
    throw FormatException('$path must be an object');
  }
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$path keys must be strings');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

List<dynamic> _list(Object? value, String path) {
  if (value is! List) {
    throw FormatException('$path must be an array');
  }
  return value;
}

String _string(Object? value, String path) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$path must be a non-empty string');
  }
  return value;
}

int _integer(Object? value, String path) {
  if (value is! int) {
    throw FormatException('$path must be an integer');
  }
  return value;
}

List<String> _strings(Object? value, String path) {
  final list = _list(value, path);
  final result = <String>[];
  for (var index = 0; index < list.length; index++) {
    result.add(_string(list[index], '$path[$index]'));
  }
  if (result.length != result.toSet().length) {
    throw FormatException('$path must not contain duplicates');
  }
  return result;
}

String _sha256(String value, String path) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw FormatException('$path must be lowercase SHA-256 hex');
  }
  return value;
}

void _expectKeys(
  Map<String, dynamic> value,
  Set<String> expected,
  String path,
) {
  final keys = value.keys.toSet();
  final missing = expected.difference(keys);
  final extra = keys.difference(expected);
  if (missing.isNotEmpty) {
    throw FormatException('$path missing keys: ${missing.join(', ')}');
  }
  if (extra.isNotEmpty) {
    throw FormatException(
      '$path has unsupported keys: ${extra.join(', ')}',
    );
  }
}

bool _sameSet(Set<String> left, Set<String> right) {
  return left.length == right.length && left.containsAll(right);
}


String _stableJson(Object? value) {
  Object? canonicalize(Object? item) {
    if (item is Map) {
      final keys = item.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: canonicalize(item[key]),
      };
    }
    if (item is List) {
      return item.map(canonicalize).toList(growable: false);
    }
    return item;
  }

  return jsonEncode(canonicalize(value));
}
