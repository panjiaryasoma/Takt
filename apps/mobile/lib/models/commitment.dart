import 'enums.dart';

/// Model data satu komitmen / jadwal.
///
/// Padanan tabel COMMITMENTS (takt_schema_v3.sql / ERD).
/// Waktu disimpan sebagai epoch **milidetik** dan wajib kelipatan menit
/// (60000 ms) — sama seperti CHECK constraint di DB, supaya nanti mulus
/// disambungkan ke Drift tanpa mengubah bentuk data.
///
/// Ini murni "bentuk data" (seperti struct + let/var di Swift). Tidak ada
/// logika penyimpanan di sini — itu tugas ViewModel / database.
class Commitment {
  Commitment({
    required this.id,
    required this.title,
    this.category,
    required this.type,
    required this.startAtEpochMs,
    required this.endAtEpochMs,
    required this.timezone,
    required this.source,
    required this.createdAtEpochMs,
    required this.updatedAtEpochMs,
  });

  final String id;
  final String title;

  /// Kategori bebas (mis. "Kuliah", "Lomba"). Boleh null di DB.
  final String? category;

  final CommitmentType type;

  /// Mulai & selesai dalam epoch ms (kelipatan 60000).
  final int startAtEpochMs;
  final int endAtEpochMs;

  /// IANA timezone, mis. "Asia/Jakarta".
  final String timezone;

  /// Asal data, mis. "manual", "import".
  final String source;

  final int createdAtEpochMs;
  final int updatedAtEpochMs;

  // ---- Helper waktu untuk dipakai di UI -----------------------------------

  DateTime get startAt => DateTime.fromMillisecondsSinceEpoch(startAtEpochMs);
  DateTime get endAt => DateTime.fromMillisecondsSinceEpoch(endAtEpochMs);

  /// Durasi dalam menit.
  int get durationMinutes => (endAtEpochMs - startAtEpochMs) ~/ 60000;

  /// Apakah komitmen ini jatuh pada tanggal [day] (abaikan jam).
  bool occursOn(DateTime day) {
    final s = startAt;
    return s.year == day.year && s.month == day.month && s.day == day.day;
  }

  // ---- Serialisasi (siap untuk Drift / SQLite nanti) ----------------------

  factory Commitment.fromMap(Map<String, Object?> map) {
    return Commitment(
      id: map['id']! as String,
      title: map['title']! as String,
      category: map['category'] as String?,
      type: CommitmentType.fromWire(map['type']! as String),
      startAtEpochMs: map['start_at_epoch_ms']! as int,
      endAtEpochMs: map['end_at_epoch_ms']! as int,
      timezone: map['timezone']! as String,
      source: map['source']! as String,
      createdAtEpochMs: map['created_at_epoch_ms']! as int,
      updatedAtEpochMs: map['updated_at_epoch_ms']! as int,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'type': type.wire,
      'start_at_epoch_ms': startAtEpochMs,
      'end_at_epoch_ms': endAtEpochMs,
      'timezone': timezone,
      'source': source,
      'created_at_epoch_ms': createdAtEpochMs,
      'updated_at_epoch_ms': updatedAtEpochMs,
    };
  }

  Commitment copyWith({
    String? id,
    String? title,
    String? category,
    CommitmentType? type,
    int? startAtEpochMs,
    int? endAtEpochMs,
    String? timezone,
    String? source,
    int? createdAtEpochMs,
    int? updatedAtEpochMs,
  }) {
    return Commitment(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      type: type ?? this.type,
      startAtEpochMs: startAtEpochMs ?? this.startAtEpochMs,
      endAtEpochMs: endAtEpochMs ?? this.endAtEpochMs,
      timezone: timezone ?? this.timezone,
      source: source ?? this.source,
      createdAtEpochMs: createdAtEpochMs ?? this.createdAtEpochMs,
      updatedAtEpochMs: updatedAtEpochMs ?? this.updatedAtEpochMs,
    );
  }
}
