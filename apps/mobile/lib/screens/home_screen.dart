import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// HomeScreen — Figma node 11:1262 ("Home").
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                Container(
                  width: 47,
                  height: 43,
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

          // Featured card (oranye)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.accent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: C.bg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: C.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          const Text(
                            'Lomba Terdekat',
                            style: TextStyle(color: C.accent, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Text(
                      '18 hari lagi',
                      style: TextStyle(
                        color: C.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Lomba Inovasi Digital Nusantara 2026',
                  style: TextStyle(
                    color: C.accentText,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '27 September 2026 - Online Project',
                  style: TextStyle(color: C.accentSub, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Kapasitas pekan ini
          const SectionHeading(
              title: 'Kapasitas pekan ini', action: 'Lihat jadwal'),
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
                  children: const [
                    _Metric(label: 'Terjadwal', value: '5,5 jam', color: C.accent),
                    SizedBox(width: 16),
                    _Metric(label: 'Tersedia', value: '8,5 jam', color: C.white),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: const LinearProgressIndicator(
                    value: 0.39, // 5,5 / (5,5+8,5)
                    minHeight: 8,
                    backgroundColor: C.white,
                    valueColor: AlwaysStoppedAnimation<Color>(C.accent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Lomba Minggu ini
          const SectionHeading(title: 'Lomba Minggu ini'),
          const SizedBox(height: 16),
          const _CompetitionRow(
            day: '18',
            month: 'Sept',
            title: 'Lomba ABC',
            detail: 'hackaton - Inovasi Digital AI /ML',
          ),
          const SizedBox(height: 16),
          const _CompetitionRow(
            day: '18',
            month: 'Sept',
            title: 'Lomba BDA',
            detail: 'hackaton - Inovasi Digital AI /ML',
          ),
          const SizedBox(height: 16),

          // Rencana Tersimpan
          const SectionHeading(title: 'Rencana Tersimpan'),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: C.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.bookmark_rounded,
                      color: C.accent, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Lihat Rencana Lomba',
                        style: TextStyle(
                          color: C.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '7 pekan · 8–11 jam per pekan',
                        style: TextStyle(color: C.navInactive, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
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

class _CompetitionRow extends StatelessWidget {
  const _CompetitionRow({
    required this.day,
    required this.month,
    required this.title,
    required this.detail,
  });

  final String day;
  final String month;
  final String title;
  final String detail;

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
            child: Text(
              '$day\n$month',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: C.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: C.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(color: C.muted2, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
