import 'package:drift/drift.dart';

import '../../models/analysis_snapshot.dart';
import '../../models/competition_analysis_wire.dart';
import '../database/app_database.dart';
import 'analysis_repository.dart';

class DriftAnalysisRepository implements AnalysisRepository {
  DriftAnalysisRepository(
    this._db, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;
  bool _initialized = false;
  bool _closed = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _db.initialize();
    _initialized = true;
  }

  @override
  Future<AnalysisSnapshot?> latestSnapshot(
    String competitionId,
  ) async {
    await initialize();
    final rows = await _db.customSelect(
      '''
SELECT * FROM analysis_snapshots
WHERE competition_id = ?
ORDER BY cached_at_epoch_ms DESC, id DESC
LIMIT 1
''',
      variables: [Variable<String>(competitionId)],
    ).get();
    if (rows.isEmpty) return null;
    return AnalysisSnapshot.fromMap(rows.single.data);
  }

  @override
  Future<List<AnalysisSnapshot>> snapshotsForCompetition(
    String competitionId,
  ) async {
    await initialize();
    final rows = await _db.customSelect(
      '''
SELECT * FROM analysis_snapshots
WHERE competition_id = ?
ORDER BY cached_at_epoch_ms, id
''',
      variables: [Variable<String>(competitionId)],
    ).get();
    return rows
        .map((row) => AnalysisSnapshot.fromMap(row.data))
        .toList(growable: false);
  }

  @override
  Future<AnalysisSnapshot> persistResponse({
    required String originalBody,
    required CompetitionAnalyzeResponseWire response,
  }) async {
    await initialize();
    final now = _now();
    final nowMs = now.millisecondsSinceEpoch;
    final competitionId = response.report.competitionId;
    final snapshot = AnalysisSnapshot(
      id:
          'analysis-$competitionId-${now.microsecondsSinceEpoch}-${response.ref.wireFingerprint.substring(0, 12)}',
      competitionId: competitionId,
      reportVersion: response.report.reportVersion,
      assemblyMaterialFingerprint:
          response.ref.assemblyMaterialFingerprint,
      sourceSetFingerprint: response.ref.sourceSetFingerprint,
      wireFingerprint: response.ref.wireFingerprint,
      reportChanged: response.reportChanged,
      responseJson: originalBody,
      cachedAtEpochMs: nowMs,
    );

    await _db.transaction(() async {
      await _db.customStatement(
        '''
INSERT INTO competitions (
  id, created_at_epoch_ms, updated_at_epoch_ms
) VALUES (?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  updated_at_epoch_ms = excluded.updated_at_epoch_ms
''',
        [competitionId, nowMs, nowMs],
      );
      await _db.customStatement(
        '''
INSERT INTO analysis_snapshots (
  id, competition_id, report_version,
  assembly_material_fingerprint, source_set_fingerprint,
  wire_fingerprint, report_changed, response_json,
  cached_at_epoch_ms
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
        [
          snapshot.id,
          snapshot.competitionId,
          snapshot.reportVersion,
          snapshot.assemblyMaterialFingerprint,
          snapshot.sourceSetFingerprint,
          snapshot.wireFingerprint,
          snapshot.reportChanged ? 1 : 0,
          snapshot.responseJson,
          snapshot.cachedAtEpochMs,
        ],
      );
    });
    return snapshot;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _db.close();
  }
}
