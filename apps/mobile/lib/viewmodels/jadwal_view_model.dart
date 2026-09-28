import 'package:flutter/foundation.dart';

import '../models/commitment.dart';
import '../models/enums.dart';

/// ViewModel jadwal — padanan ViewModel di SwiftUI (@Published + fungsi).
///
/// Menyimpan state jadwal dan menyediakan fungsi baca/tulis untuk View.
/// SUMBER DATA SEKARANG: list di memori (belum ada database).
/// Nanti tinggal ganti isi [_all] dengan hasil query Drift — View dan Model
/// tidak perlu diubah. Itulah gunanya memisahkan lapisan ini.
class JadwalViewModel extends ChangeNotifier {
  JadwalViewModel();

  final List<Commitment> _all = [];

  /// Tanggal yang sedang dipilih di kalender. Default: hari ini.
  DateTime _selectedDate = _dateOnly(DateTime.now());

  // ---- Getter untuk View ---------------------------------------------------

  /// Semua komitmen (read-only bagi View).
  List<Commitment> get all => List.unmodifiable(_all);

  DateTime get selectedDate => _selectedDate;

  /// Komitmen pada tanggal terpilih, terurut berdasarkan jam mulai.
  List<Commitment> get itemsForSelectedDate {
    final items = _all.where((c) => c.occursOn(_selectedDate)).toList()
      ..sort((a, b) => a.startAtEpochMs.compareTo(b.startAtEpochMs));
    return items;
  }

  /// Komitmen pada [day] tertentu (dipakai Home / ringkasan).
  List<Commitment> itemsOn(DateTime day) {
    final items = _all.where((c) => c.occursOn(day)).toList()
      ..sort((a, b) => a.startAtEpochMs.compareTo(b.startAtEpochMs));
    return items;
  }

  /// Nomor tanggal (1..31) pada [month] yang punya komitmen — untuk dot kalender.
  Set<int> eventDaysOfMonth(DateTime month) {
    return _all
        .where((c) =>
            c.startAt.year == month.year && c.startAt.month == month.month)
        .map((c) => c.startAt.day)
        .toSet();
  }

  /// Total menit terjadwal pada [day].
  int scheduledMinutesOn(DateTime day) {
    return itemsOn(day).fold(0, (sum, c) => sum + c.durationMinutes);
  }

  // ---- Aksi (dipanggil View) ----------------------------------------------

  /// Pilih tanggal (mis. saat sel kalender diklik).
  void selectDate(DateTime day) {
    _selectedDate = _dateOnly(day);
    notifyListeners();
  }

  /// Pilih tanggal berdasarkan nomor hari dalam bulan terpilih.
  void selectDay(int day, {DateTime? inMonth}) {
    final m = inMonth ?? _selectedDate;
    selectDate(DateTime(m.year, m.month, day));
  }

  /// Tambah komitmen baru dari form. Mengembalikan komitmen yang dibuat.
  /// [category] dipakai menyimpan deskripsi singkat (skema commitments tidak
  /// punya kolom deskripsi terpisah).
  Commitment tambah({
    required String title,
    String? category,
    required DateTime start,
    required DateTime end,
    CommitmentType type = CommitmentType.fixed,
    String timezone = 'Asia/Jakarta',
    String source = 'manual',
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final c = Commitment(
      id: 'cmt_${now}_${_all.length}',
      title: title,
      category: category,
      type: type,
      startAtEpochMs: _floorToMinute(start.millisecondsSinceEpoch),
      endAtEpochMs: _floorToMinute(end.millisecondsSinceEpoch),
      timezone: timezone,
      source: source,
      createdAtEpochMs: now,
      updatedAtEpochMs: now,
    );
    _all.add(c);
    // Loncat ke tanggal komitmen baru supaya langsung terlihat.
    _selectedDate = _dateOnly(start);
    notifyListeners();
    return c;
  }

  void hapus(String id) {
    _all.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  /// Tambah jadwal WAJIB (rutin mingguan) pada [weekdays] (1=Sen..7=Min).
  /// Untuk sekarang di-expand jadi beberapa kejadian nyata beberapa pekan ke
  /// depan (default 12 pekan) supaya langsung tampil di kalender. Nanti saat
  /// pindah ke DB, ini menjadi satu Commitment + satu RecurrenceRule.
  void tambahRutin({
    required String title,
    String? category,
    required Set<int> weekdays,
    required int jamMulai,
    required int menitMulai,
    required int jamSelesai,
    required int menitSelesai,
    int pekan = 12,
    DateTime? mulaiDari,
    String timezone = 'Asia/Jakarta',
  }) {
    if (weekdays.isEmpty) return;
    final base = _dateOnly(mulaiDari ?? DateTime.now());
    final now = DateTime.now().millisecondsSinceEpoch;
    DateTime? pertama;
    var idx = 0;

    for (var w = 0; w < pekan; w++) {
      for (var d = 0; d < 7; d++) {
        final hari = base.add(Duration(days: w * 7 + d));
        if (!weekdays.contains(hari.weekday)) continue;
        if (hari.isBefore(base)) continue;
        final start =
            DateTime(hari.year, hari.month, hari.day, jamMulai, menitMulai);
        final end = DateTime(
            hari.year, hari.month, hari.day, jamSelesai, menitSelesai);
        if (!end.isAfter(start)) continue;
        _all.add(Commitment(
          id: 'rutin_${now}_${idx++}',
          title: title,
          category: category,
          type: CommitmentType.fixed,
          startAtEpochMs: _floorToMinute(start.millisecondsSinceEpoch),
          endAtEpochMs: _floorToMinute(end.millisecondsSinceEpoch),
          timezone: timezone,
          source: 'manual-rutin',
          createdAtEpochMs: now,
          updatedAtEpochMs: now,
        ));
        pertama ??= start;
      }
    }
    if (pertama != null) _selectedDate = _dateOnly(pertama);
    notifyListeners();
  }

  // ---- Util privat ---------------------------------------------------------

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Bulatkan epoch ms ke menit terdekat ke bawah (DB wajib kelipatan 60000).
  static int _floorToMinute(int epochMs) => (epochMs ~/ 60000) * 60000;
}
