/// Model COMPETITIONS — entitas lomba/kompetisi.
/// Detail lomba (nama, deadline, dsb.) hidup di dalam response_json evaluasi;
/// tabel ini sengaja minimal (identity + timestamp) sesuai skema.
class Competition {
  Competition({
    required this.id,
    required this.createdAtEpochMs,
    required this.updatedAtEpochMs,
  });

  final String id;
  final int createdAtEpochMs;
  final int updatedAtEpochMs;

  DateTime get createdAt =>
      DateTime.fromMillisecondsSinceEpoch(createdAtEpochMs);

  factory Competition.fromMap(Map<String, Object?> m) => Competition(
        id: m['id']! as String,
        createdAtEpochMs: m['created_at_epoch_ms']! as int,
        updatedAtEpochMs: m['updated_at_epoch_ms']! as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'created_at_epoch_ms': createdAtEpochMs,
        'updated_at_epoch_ms': updatedAtEpochMs,
      };

  Competition copyWith({int? updatedAtEpochMs}) => Competition(
        id: id,
        createdAtEpochMs: createdAtEpochMs,
        updatedAtEpochMs: updatedAtEpochMs ?? this.updatedAtEpochMs,
      );
}
