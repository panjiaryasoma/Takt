import 'package:flutter/foundation.dart';

/// Status sebuah rencana lomba.
/// - tersimpan : hasil analisis disimpan, BELUM diputuskan ikut/tidak (Tinjau)
/// - disetujui : sudah diputuskan diikuti, jadwal masuk kalender (Cek Jadwal)
enum RencanaStatus { tersimpan, disetujui }

/// Satu entri rencana lomba tersimpan.
/// Nanti ini gabungan SavedPlan + Competition + Evaluation dari DB; sekarang
/// bentuk ringkas untuk UI.
class SavedPlanEntry {
  SavedPlanEntry({
    required this.id,
    required this.competitionId,
    required this.title,
    required this.deadline,
    required this.status,
    this.decidedAt,
    this.decidedBy,
  });

  final String id;
  final String competitionId;
  final String title;

  /// Batas waktu lomba (dipakai `Sebelum <tgl>`).
  final DateTime deadline;

  RencanaStatus status;

  /// Kapan disetujui (untuk history "21 Sep · oleh Anda").
  final DateTime? decidedAt;
  final String? decidedBy;

  SavedPlanEntry copyWith({
    RencanaStatus? status,
    DateTime? decidedAt,
    String? decidedBy,
  }) =>
      SavedPlanEntry(
        id: id,
        competitionId: competitionId,
        title: title,
        deadline: deadline,
        status: status ?? this.status,
        decidedAt: decidedAt ?? this.decidedAt,
        decidedBy: decidedBy ?? this.decidedBy,
      );
}

/// ViewModel daftar rencana lomba (tersimpan & disetujui).
class RencanaViewModel extends ChangeNotifier {
  final List<SavedPlanEntry> _entries = [];

  /// Rencana yang belum diputuskan (tampil di "Rencana tersimpan").
  List<SavedPlanEntry> get tersimpan =>
      _entries.where((e) => e.status == RencanaStatus.tersimpan).toList();

  /// Rencana yang sudah disetujui (tampil di "History Rencana Disetujui").
  List<SavedPlanEntry> get disetujui =>
      _entries.where((e) => e.status == RencanaStatus.disetujui).toList();

  bool get kosong => _entries.isEmpty;

  /// Simpan hasil analisis sebagai rencana (dipanggil dari layar Review Brief
  /// saat user pilih "Simpan").
  SavedPlanEntry simpan({
    required String competitionId,
    required String title,
    required DateTime deadline,
  }) {
    final e = SavedPlanEntry(
      id: 'plan_${DateTime.now().millisecondsSinceEpoch}',
      competitionId: competitionId,
      title: title,
      deadline: deadline,
      status: RencanaStatus.tersimpan,
    );
    _entries.add(e);
    notifyListeners();
    return e;
  }

  /// Setujui rencana → pindah ke history disetujui.
  void setujui(String id, {String by = 'Anda'}) {
    final i = _entries.indexWhere((e) => e.id == id);
    if (i < 0) return;
    _entries[i] = _entries[i].copyWith(
      status: RencanaStatus.disetujui,
      decidedAt: DateTime.now(),
      decidedBy: by,
    );
    notifyListeners();
  }

  void hapus(String id) {
    _entries.removeWhere((e) => e.id == id);
    notifyListeners();
  }
}
