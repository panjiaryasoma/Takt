import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import '../viewmodels/jadwal_view_model.dart';
import '../widgets/common.dart';

/// HomeScreen — Figma node 11:1262 ("Home").
/// Kapasitas pekan ini dihitung dari data jadwal ([JadwalViewModel]).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.onLihatJadwal});

  /// Dipanggil saat "Lihat jadwal" ditekan (pindah ke tab Jadwal).
  final VoidCallback? onLihatJadwal;

  /// Menit terjadwal pada 7 hari pekan berjalan (Senin–Minggu).
  static int _scheduledThisWeek(JadwalViewModel vm) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    var total = 0;
    for (var i = 0; i < 7; i++) {
      total += vm.scheduledMinutesOn(monday.add(Duration(days: i)));
    }
    return total;
  }

  static String _jam(int menit) {
    final j = menit / 60.0;
    final s = j.toStringAsFixed(1).replaceAll('.', ',');
    return '$s jam';
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<JadwalViewModel>();
    final terjadwalMenit = _scheduledThisWeek(vm);
    // Kapasitas mingguan = 7 hari x preferensi (default 120 menit/hari fokus).
    const kapasitasMenit = 7 * 120;
    final tersediaMenit =
        (kapasitasMenit - terjadwalMenit).clamp(0, kapasitasMenit);
    final rasio = kapasitasMenit == 0
        ? 0.0
        : (terjadwalMenit / kapasitasMenit).clamp(0.0, 1.0);
    final adaJadwal = vm.all.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: logo Tk + welcome
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 47,
                  height: 43,
                  child: Image.asset(
                    C.logoAsset,
                    width: 47,
                    height: 43,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stack) => Container(
                      decoration: BoxDecoration(
                        color: C.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Tk',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                const Text(
                  'Welcome, Raka',
                  style: TextStyle(color: C.white, fontSize: 20),
                ),
              ],
            ),
          ),
          const HeaderDivider(),
          const SizedBox(height: 16),

          // Kapasitas pekan ini — dihitung dari data jadwal
          SectionHeading(
              title: 'Kapasitas pekan ini',
              action: 'Lihat jadwal',
              onAction: onLihatJadwal),
          const SizedBox(height: 16),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _Metric(
                        label: 'Terjadwal',
                        value: _jam(terjadwalMenit),
                        color: C.accent),
                    const SizedBox(width: 16),
                    _Metric(
                        label: 'Tersedia',
                        value: _jam(tersediaMenit),
                        color: C.white),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: rasio,
                    minHeight: 8,
                    backgroundColor: C.white,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(C.accent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Lomba Minggu ini — belum ada domain kompetisi, tampil empty-state
          const SectionHeading(title: 'Lomba Minggu ini'),
          const SizedBox(height: 16),
          const _EmptyCard(
            icon: Icons.emoji_events_outlined,
            text: 'Belum ada lomba. Tambahkan dari tab Analisis.',
          ),
          const SizedBox(height: 16),

          // Rencana Tersimpan — empty-state sampai ada rencana tersimpan
          const SectionHeading(title: 'Rencana Tersimpan'),
          const SizedBox(height: 16),
          _EmptyCard(
            icon: Icons.bookmark_border_rounded,
            text: adaJadwal
                ? 'Belum ada rencana tersimpan.'
                : 'Belum ada rencana. Susun jadwal dulu.',
          ),
        ],
      ),
    );
  }
}

/// Kartu empty-state generik (ikon + teks abu).
class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: C.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: C.accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: C.detailMuted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
                color: color, fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
