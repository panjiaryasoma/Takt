import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import '../viewmodels/jadwal_view_model.dart';
import '../widgets/common.dart';

/// HomeScreen — Figma node 11:1262 ("Home").
/// Ringkasan jadwal lokal. Availability authoritative dihitung backend saat evaluasi.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.onLihatJadwal});

  final VoidCallback? onLihatJadwal;

  static int _scheduledThisWeek(JadwalViewModel vm) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    var total = 0;
    for (var index = 0; index < 7; index++) {
      total += vm.scheduledMinutesOn(monday.add(Duration(days: index)));
    }
    return total;
  }

  static String _jam(int menit) {
    final jam = menit / 60.0;
    final text = jam.toStringAsFixed(1).replaceAll('.', ',');
    return '$text jam';
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<JadwalViewModel>();
    final terjadwalMenit = _scheduledThisWeek(vm);
    final batasProyekHarianMenit = vm.preferences.maxProjectMinutesPerDay;
    final adaJadwal = vm.all.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                  'Selamat datang',
                  style: TextStyle(color: C.white, fontSize: 20),
                ),
              ],
            ),
          ),
          const HeaderDivider(),
          if (vm.isLoading) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 16),
          SectionHeading(
            title: 'Ringkasan pekan ini',
            action: 'Lihat jadwal',
            onAction: onLihatJadwal,
          ),
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
                      label: 'Komitmen minggu ini',
                      value: _jam(terjadwalMenit),
                      color: C.accent,
                    ),
                    const SizedBox(width: 16),
                    _Metric(
                      label: 'Batas proyek / hari',
                      value: _jam(batasProyekHarianMenit),
                      color: C.white,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Availability dihitung backend saat evaluasi rencana.',
                    style: TextStyle(color: C.detailMuted, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          if (vm.errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: C.card,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      vm.errorMessage!,
                      style: const TextStyle(color: C.detailMuted, fontSize: 12),
                    ),
                  ),
                  TextButton(onPressed: vm.retry, child: const Text('Coba lagi')),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          const SectionHeading(title: 'Lomba Minggu ini'),
          const SizedBox(height: 16),
          const _EmptyCard(
            icon: Icons.emoji_events_outlined,
            text: 'Belum ada lomba. Tambahkan dari tab Analisis.',
          ),
          const SizedBox(height: 16),
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
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
