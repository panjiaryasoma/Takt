/// Model ANALYSIS_SNAPSHOTS — snapshot hasil analisis satu kompetisi.
/// response_json menyimpan payload wire dari backend (otoritatif).
class AnalysisSnapshot {
  AnalysisSnapshot({
    required this.id,
    required this.competitionId,
    required this.reportVersion,
    required this.assemblyMaterialFingerprint,
    this.sourceSetFingerprint,
    required this.wireFingerprint,
    required this.reportChanged,
    required this.responseJson,
    required this.cachedAtEpochMs,
  });

  final String id;
  final String competitionId;

  /// Versi laporan (>= 1).
  final int reportVersion;

  /// Fingerprint 64-char (hex sha-256).
  final String assemblyMaterialFingerprint;
  final String? sourceSetFingerprint;
  final String wireFingerprint;

  /// Apakah laporan berubah dibanding versi sebelumnya.
  final bool reportChanged;

  /// JSON respons backend (disimpan mentah, jangan dipecah).
  final String responseJson;

  final int cachedAtEpochMs;

  DateTime get cachedAt => DateTime.fromMillisecondsSinceEpoch(cachedAtEpochMs);

  factory AnalysisSnapshot.fromMap(Map<String, Object?> m) => AnalysisSnapshot(
        id: m['id']! as String,
        competitionId: m['competition_id']! as String,
        reportVersion: m['report_version']! as int,
        assemblyMaterialFingerprint:
            m['assembly_material_fingerprint']! as String,
        sourceSetFingerprint: m['source_set_fingerprint'] as String?,
        wireFingerprint: m['wire_fingerprint']! as String,
        reportChanged: (m['report_changed']! as int) == 1,
        responseJson: m['response_json']! as String,
        cachedAtEpochMs: m['cached_at_epoch_ms']! as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'competition_id': competitionId,
        'report_version': reportVersion,
        'assembly_material_fingerprint': assemblyMaterialFingerprint,
        'source_set_fingerprint': sourceSetFingerprint,
        'wire_fingerprint': wireFingerprint,
        'report_changed': reportChanged ? 1 : 0,
        'response_json': responseJson,
        'cached_at_epoch_ms': cachedAtEpochMs,
      };
}
