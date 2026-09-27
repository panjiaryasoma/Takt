import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'jadwal_harian_screen.dart' show JadwalTabs;

/// JadwalRingkasanScreen — Figma node 57:1568 (tab Ringkasan Pekan).
/// Heatmap kapasitas 7 hari × 11 jam (07–17).
class JadwalRingkasanScreen extends StatelessWidget {
  const JadwalRingkasanScreen({super.key, required this.onSwitchTab});

  final ValueChanged<int> onSwitchTab;

  static const _hours = [
    '07', '08', '09', '10', '11', '12', '13', '14', '15', '16', '17'
  ];
  static const _days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

  // Intensitas per (hari, jam) — persis dari Figma.
  static const _raw = <String, List<String>>{
    'Sen': ['k', 'sb', 'sb', 'sd', 'r', 'k', 'sd', 'sd', 'r', 'k', 'k'],
    'Sel': ['k', 'r', 'p', 'p', 'sd', 'k', 'sb', 'sb', 'sd', 'r', 'k'],
    'Rab': ['k', 'sd', 'sd', 'r', 'k', 'k', 'r', 'sb', 'sb', 'sd', 'k'],
    'Kam': ['k', 'sb', 'sb', 'sb', 'sd', 'k', 'r', 'r', 'p', 'p', 'r'],
    'Jum': ['k', 'sd', 'sd', 'sb', 'sb', 'k', 'sd', 'sd', 'r', 'k', 'k'],
    'Sab': ['r', 'sb', 'sb', 'sd', 'k', 'k', 'sb', 'sd', 'sb', 'r', 'k'],
    'Min': ['k', 'k', 'r', 'r', 'k', 'k', 'k', 'r', 'k', 'k', 'k'],
  };

  static const _intensity = <String, Color>{
    'k': C.kosong,
    'r': C.ringan,
    'sd': C.sedang,
    'sb': C.sibuk,
    'p': C.padat,
  };

  static const _legend = <(Color, String)>[
    (C.kosong, 'Kosong'),
    (C.ringan, 'Ringan'),
    (C.sedang, 'Sedang'),
    (C.sibuk, 'Sibuk'),
    (C.padat, 'Padat'),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppHeader(title: 'Jadwal Saya'),
          const HeaderDivider(),
          const SizedBox(height: 16),

          JadwalTabs(activeIndex: 1, onChanged: onSwitchTab),
          const SizedBox(height: 16),

          // Ringkasan Pekan Ini — heatmap card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ringkasan Pekan Ini',
                  style: TextStyle(
                    color: C.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),

                // Legend
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: _legend
                      .map((l) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: l.$1,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                l.$2,
                                style: const TextStyle(
                                    color: C.navInactive, fontSize: 9),
                              ),
                            ],
                          ))
                      .toList(),
                ),
                const SizedBox(height: 10),

                // Hours header
                Row(
                  children: [
                    const SizedBox(width: 26),
                    ..._hours.map((h) => Expanded(
                          child: Center(
                            child: Text(
                              h,
                              style: const TextStyle(
                                  color: C.navInactive, fontSize: 8),
                            ),
                          ),
                        )),
                  ],
                ),
                const SizedBox(height: 2),

                // Heatmap rows
                ..._days.map((day) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 26,
                            child: Text(
                              day,
                              style: TextStyle(
                                color: day == 'Sab' ? C.accent : C.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          ..._raw[day]!.map((lvl) => Expanded(
                                child: Container(
                                  height: 18,
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: BoxDecoration(
                                    color: _intensity[lvl]!.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              )),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
