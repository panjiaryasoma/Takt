import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// ProgresAnalisisScreen — Figma node 11:1473 ("Progres Analisis").
/// Progress ring + daftar langkah analisis + peringatan konflik + Baca Hasil.
class ProgresAnalisisScreen extends StatelessWidget {
  const ProgresAnalisisScreen({super.key, this.onReadResult});

  final VoidCallback? onReadResult;

  static const _steps = <_Step>[
    _Step('Membaca sumber resmi', '3 dokumen · provenance disimpan',
        _StepState.done),
    _Step('Menyusun estimasi kerja', '', _StepState.done),
    _Step('Mencocokkan kalender', 'Menggunakan 8,5 jam tersedia',
        _StepState.process),
    _Step('Menilai risiko dan alternatif', 'Belum dimulai', _StepState.waiting),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppHeader(title: 'Progres Analisis'),
          const HeaderDivider(),
          const SizedBox(height: 16),

          // Progress ring card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: C.accent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                SizedBox(
                  width: 130,
                  height: 130,
                  child: CustomPaint(
                    painter: _RingPainter(0.72),
                    child: const Center(
                      child: Text(
                        '72%',
                        style: TextStyle(
                          color: C.bg,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: C.bg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.access_time, color: C.white, size: 13),
                      SizedBox(width: 6),
                      Text('± 40 detik',
                          style: TextStyle(color: C.white, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Memeriksa kelayakan terhadap kapasitas nyata Anda.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: C.accentText, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          const SectionHeading(title: 'Langkah analisis'),
          const SizedBox(height: 16),

          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: _steps.map((s) => _StepRow(step: s)).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // Konflik tanggal
          Container(
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
                  child: const Icon(Icons.warning_amber_rounded,
                      color: C.sedang, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Konflik tanggal terdeteksi',
                          style: TextStyle(
                              color: C.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      SizedBox(height: 3),
                      Text(
                        'Halaman utama: 15 Nov · PDF: 12 Nov. Anda akan diminta meninjau.',
                        style:
                            TextStyle(color: C.detailMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Baca Hasil
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GestureDetector(
              onTap: onReadResult,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: C.accent,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Baca Hasil',
                  style: TextStyle(
                    color: C.bg,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Anda dapat meninggalkan layar ini. Tidak ada perubahan kalender yang dibuat.',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.navInactive, fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

enum _StepState { done, process, waiting }

class _Step {
  const _Step(this.title, this.detail, this.state);
  final String title;
  final String detail;
  final _StepState state;
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});
  final _Step step;

  @override
  Widget build(BuildContext context) {
    late final IconData leadIcon;
    late final Color leadColor;
    late final String badge;
    late final IconData badgeIcon;
    switch (step.state) {
      case _StepState.done:
        leadIcon = Icons.check_circle;
        leadColor = C.kosong;
        badge = 'Selesai';
        badgeIcon = Icons.check_circle_outline;
        break;
      case _StepState.process:
        leadIcon = Icons.sync;
        leadColor = C.accent;
        badge = 'Proses';
        badgeIcon = Icons.timelapse;
        break;
      case _StepState.waiting:
        leadIcon = Icons.radio_button_unchecked;
        leadColor = C.navInactive;
        badge = 'Menunggu';
        badgeIcon = Icons.schedule;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(leadIcon, color: leadColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.title,
                    style: const TextStyle(
                        color: C.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                if (step.detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(step.detail,
                      style: const TextStyle(
                          color: C.detailMuted, fontSize: 11)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            children: [
              Icon(badgeIcon, color: leadColor, size: 14),
              const SizedBox(width: 4),
              Text(badge,
                  style: TextStyle(color: leadColor, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Progress ring painter: track + arc.
class _RingPainter extends CustomPainter {
  _RingPainter(this.value);
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 8;
    const stroke = 12.0;

    final track = Paint()
      ..color = C.bg.withValues(alpha: 0.35)
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final arc = Paint()
      ..color = C.bg
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.value != value;
}
