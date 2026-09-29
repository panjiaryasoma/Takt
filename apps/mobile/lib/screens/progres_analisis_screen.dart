import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/analysis_step.dart';
import '../theme/app_theme.dart';
import '../viewmodels/analisis_view_model.dart';
import '../widgets/common.dart';

/// ProgresAnalisisScreen — Figma node 11:1473 ("Progres Analisis").
/// Progress ring beranimasi + daftar langkah + konflik + Baca Hasil.
/// Data dari [AnalisisViewModel] (simulasi sekarang, AI model nanti).
class ProgresAnalisisScreen extends StatefulWidget {
  const ProgresAnalisisScreen({super.key, this.onReadResult});

  final VoidCallback? onReadResult;

  @override
  State<ProgresAnalisisScreen> createState() => _ProgresAnalisisScreenState();
}

class _ProgresAnalisisScreenState extends State<ProgresAnalisisScreen> {
  @override
  void initState() {
    super.initState();
    // Mulai simulasi saat layar dibuka (idempotent).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AnalisisViewModel>().mulaiSimulasi();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AnalisisViewModel>();
    final etaText = vm.etaDetik == null
        ? '…'
        : (vm.etaDetik! <= 0 ? 'selesai' : '± ${vm.etaDetik} detik');

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppHeader(title: 'Progres Analisis'),
          const HeaderDivider(),
          const SizedBox(height: 16),

          // Progress ring card (beranimasi)
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
                  child: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                    tween: Tween(begin: 0, end: vm.progress),
                    builder: (context, value, _) => CustomPaint(
                      painter: _RingPainter(value),
                      child: Center(
                        child: Text(
                          '${(value * 100).round()}%',
                          style: const TextStyle(
                            color: C.bg,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                          ),
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
                    children: [
                      const Icon(Icons.access_time, color: C.white, size: 13),
                      const SizedBox(width: 6),
                      Text(etaText,
                          style: const TextStyle(
                              color: C.white, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    vm.statusText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: C.accentText, fontSize: 13),
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
              children:
                  vm.steps.map((s) => _StepRow(step: s)).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // Konflik tanggal (muncul bila ada)
          if (vm.konflikText != null) ...[
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
                      children: [
                        const Text('Konflik tanggal terdeteksi',
                            style: TextStyle(
                                color: C.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(
                          vm.konflikText!,
                          style: const TextStyle(
                              color: C.detailMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Baca Hasil — aktif saat selesai
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GestureDetector(
              onTap: vm.selesai ? widget.onReadResult : null,
              child: Opacity(
                opacity: vm.selesai ? 1 : 0.5,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: C.accent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    vm.selesai ? 'Baca Hasil' : 'Menganalisis…',
                    style: const TextStyle(
                      color: C.bg,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
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

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});
  final AnalysisStep step;

  @override
  Widget build(BuildContext context) {
    late final IconData leadIcon;
    late final Color leadColor;
    late final String badge;
    late final IconData badgeIcon;
    switch (step.state) {
      case AnalysisStepState.done:
        leadIcon = Icons.check_circle;
        leadColor = C.kosong;
        badge = 'Selesai';
        badgeIcon = Icons.check_circle_outline;
        break;
      case AnalysisStepState.process:
        leadIcon = Icons.sync;
        leadColor = C.accent;
        badge = 'Proses';
        badgeIcon = Icons.timelapse;
        break;
      case AnalysisStepState.waiting:
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
              Text(badge, style: TextStyle(color: leadColor, fontSize: 11)),
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
