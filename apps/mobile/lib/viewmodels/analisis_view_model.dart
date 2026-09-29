import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/analysis_step.dart';

/// ViewModel proses analisis AI.
///
/// TITIK INTEGRASI AI: sekarang jalan pakai SIMULASI (timer) supaya UI hidup.
/// Saat model AI temanmu siap, ganti [mulaiSimulasi] dengan stream/callback
/// yang memanggil [terapkanProgress] / [setLangkah] dari progress event asli.
/// View tidak perlu berubah — cukup baca [progress], [steps], [etaDetik], dll.
class AnalisisViewModel extends ChangeNotifier {
  AnalysisPhase _phase = AnalysisPhase.idle;

  /// 0.0..1.0
  double _progress = 0;

  /// Estimasi sisa waktu (detik). null = tak diketahui.
  int? _etaDetik;

  String _statusText = 'Menyiapkan analisis…';
  String? _konflikText;

  List<AnalysisStep> _steps = const [
    AnalysisStep(
        title: 'Membaca sumber resmi', detail: 'Menunggu dokumen'),
    AnalysisStep(title: 'Menyusun estimasi kerja'),
    AnalysisStep(title: 'Mencocokkan kalender'),
    AnalysisStep(title: 'Menilai risiko dan alternatif'),
  ];

  Timer? _timer;

  // ---- Getter untuk View ---------------------------------------------------

  AnalysisPhase get phase => _phase;
  double get progress => _progress;
  int? get etaDetik => _etaDetik;
  String get statusText => _statusText;
  String? get konflikText => _konflikText;
  List<AnalysisStep> get steps => List.unmodifiable(_steps);
  bool get selesai => _phase == AnalysisPhase.done;
  int get persen => (_progress * 100).round();

  // ---- Titik integrasi AI (dipanggil dari backend/stream nanti) -----------

  /// Perbarui progress & ETA dari event AI.
  void terapkanProgress({
    required double progress,
    int? etaDetik,
    String? statusText,
  }) {
    _progress = progress.clamp(0.0, 1.0);
    _etaDetik = etaDetik;
    if (statusText != null) _statusText = statusText;
    if (_progress >= 1.0) {
      _phase = AnalysisPhase.done;
      _etaDetik = 0;
    }
    notifyListeners();
  }

  /// Ganti seluruh daftar langkah (mis. dari respons AI).
  void setLangkah(List<AnalysisStep> steps) {
    _steps = steps;
    notifyListeners();
  }

  /// Perbarui satu langkah berdasarkan indeks.
  void updateLangkah(int index, AnalysisStep step) {
    if (index < 0 || index >= _steps.length) return;
    final next = [..._steps];
    next[index] = step;
    _steps = next;
    notifyListeners();
  }

  void setKonflik(String? text) {
    _konflikText = text;
    notifyListeners();
  }

  // ---- Simulasi (dipakai sebelum AI model siap) ----------------------------

  /// Jalankan simulasi progress bertahap. Aman dipanggil ulang.
  void mulaiSimulasi() {
    _timer?.cancel();
    _phase = AnalysisPhase.running;
    _progress = 0;
    _etaDetik = 55;
    _statusText = 'Membaca sumber resmi…';
    _konflikText = null;
    _steps = const [
      AnalysisStep(
          title: 'Membaca sumber resmi',
          detail: '3 dokumen · provenance disimpan',
          state: AnalysisStepState.process),
      AnalysisStep(title: 'Menyusun estimasi kerja'),
      AnalysisStep(title: 'Mencocokkan kalender'),
      AnalysisStep(title: 'Menilai risiko dan alternatif'),
    ];
    notifyListeners();

    const tick = Duration(milliseconds: 400);
    _timer = Timer.periodic(tick, (t) {
      // Naik ~3% per tick.
      _progress = (_progress + 0.03).clamp(0.0, 1.0);
      _etaDetik = ((1 - _progress) * 55).round();

      // Pindahkan status langkah sesuai ambang progress.
      _steps = _langkahUntuk(_progress);
      _statusText = _statusUntuk(_progress);

      if (_progress >= 1.0) {
        _phase = AnalysisPhase.done;
        _etaDetik = 0;
        _konflikText =
            'Halaman utama: 15 Nov · PDF: 12 Nov. Anda akan diminta meninjau.';
        t.cancel();
      }
      notifyListeners();
    });
  }

  void reset() {
    _timer?.cancel();
    _phase = AnalysisPhase.idle;
    _progress = 0;
    _etaDetik = null;
    _statusText = 'Menyiapkan analisis…';
    _konflikText = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ---- Helper simulasi -----------------------------------------------------

  List<AnalysisStep> _langkahUntuk(double p) {
    AnalysisStepState s(double ambangSelesai, double ambangMulai) {
      if (p >= ambangSelesai) return AnalysisStepState.done;
      if (p >= ambangMulai) return AnalysisStepState.process;
      return AnalysisStepState.waiting;
    }

    return [
      AnalysisStep(
        title: 'Membaca sumber resmi',
        detail: '3 dokumen · provenance disimpan',
        state: s(0.25, 0.0),
      ),
      AnalysisStep(
        title: 'Menyusun estimasi kerja',
        detail: p >= 0.25 ? 'Estimasi effort dihitung' : '',
        state: s(0.55, 0.25),
      ),
      AnalysisStep(
        title: 'Mencocokkan kalender',
        detail: p >= 0.55 ? 'Menggunakan kapasitas tersedia' : '',
        state: s(0.85, 0.55),
      ),
      AnalysisStep(
        title: 'Menilai risiko dan alternatif',
        detail: p >= 0.85 ? 'Menyusun alternatif' : 'Belum dimulai',
        state: s(1.0, 0.85),
      ),
    ];
  }

  String _statusUntuk(double p) {
    if (p < 0.25) return 'Membaca sumber resmi…';
    if (p < 0.55) return 'Menyusun estimasi kerja…';
    if (p < 0.85) return 'Memeriksa kelayakan terhadap kapasitas nyata Anda.';
    if (p < 1.0) return 'Menilai risiko dan alternatif…';
    return 'Analisis selesai.';
  }
}
