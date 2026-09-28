import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'jadwal_harian_screen.dart' show JadwalTabs;

/// Satu batang aktivitas pada Gantt chart.
class _Task {
  const _Task(this.label, this.start, this.end, this.color);

  final String label;
  final int start; // jam mulai (inklusif), skala 07–18
  final int end; // jam selesai (eksklusif)
  final Color color;
}

/// JadwalRingkasanScreen — tab Ringkasan Pekan (Gantt chart mingguan).
/// 7 hari (baris) × jam 07–17 (kolom), batang aktivitas memanjang sesuai durasi.
class JadwalRingkasanScreen extends StatelessWidget {
  const JadwalRingkasanScreen({super.key, required this.onSwitchTab});

  final ValueChanged<int> onSwitchTab;

  static const int _startHour = 7; // 07:00
  static const int _endHour = 18; // 18:00 (11 slot)
  static const int _slots = _endHour - _startHour;

  static const _days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

  // Aktivitas per hari — batang Gantt (start, end dalam jam 24h).
  static const _tasks = <String, List<_Task>>{
    'Sen': [
      _Task('Kelas', 8, 10, C.dotBlue),
      _Task('Latihan Lomba', 13, 15, C.dotPurple),
    ],
    'Sel': [
      _Task('Rapat Tim', 9, 11, C.padat),
      _Task('Kerja Proyek', 13, 15, C.dotBlue),
    ],
    'Rab': [
      _Task('Riset', 8, 10, C.dotGreen),
      _Task('Bimbingan', 14, 16, C.sibuk),
    ],
    'Kam': [
      _Task('Kelas', 8, 11, C.dotBlue),
      _Task('Deadline', 15, 17, C.padat),
    ],
    'Jum': [
      _Task('Persiapan Lomba', 8, 11, C.sibuk),
      _Task('Review', 13, 15, C.dotPurple),
    ],
    'Sab': [
      _Task('Lomba', 8, 12, C.accent),
      _Task('Evaluasi', 13, 15, C.dotGreen),
    ],
    'Min': [
      _Task('Istirahat', 10, 12, C.ringan),
    ],
  };

  static const _legend = <(Color, String)>[
    (C.dotBlue, 'Kelas / Kerja'),
    (C.dotPurple, 'Latihan'),
    (C.sibuk, 'Persiapan'),
    (C.padat, 'Deadline'),
    (C.accent, 'Lomba'),
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
                  'Gantt Chart Pekan Ini',
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
                const SizedBox(height: 12),

                // Hours header
                Row(
                  children: [
                    const SizedBox(width: 30),
                    ...List.generate(_slots, (i) {
                      final h = _startHour + i;
                      return Expanded(
                        child: Center(
                          child: Text(
                            h.toString().padLeft(2, '0'),
                            style: const TextStyle(
                                color: C.navInactive, fontSize: 8),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 4),

                // Gantt rows
                ..._days.map((day) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 30,
                            child: Text(
                              day,
                              style: TextStyle(
                                color: day == 'Sab' ? C.accent : C.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Expanded(
                            child: _GanttRow(tasks: _tasks[day] ?? const []),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Ringkasan pekan: jumlah tugas wajib & lomba
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ringkasan Pekan',
                  style: TextStyle(
                    color: C.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _SummaryTile(
                      icon: Icons.menu_book_rounded,
                      color: C.dotBlue,
                      value: '${_hitungWajib()}',
                      label: 'Tugas wajib',
                      hint: 'Kuliah, kerja, rapat',
                    ),
                    const SizedBox(width: 12),
                    _SummaryTile(
                      icon: Icons.emoji_events_rounded,
                      color: C.accent,
                      value: '${_hitungLomba()}',
                      label: 'Lomba',
                      hint: 'Dijalankan pekan ini',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Tugas wajib = aktivitas rutin non-lomba (Kelas/Kerja/Rapat/Bimbingan/
  /// Deadline). Diidentifikasi dari label & warna.
  static int _hitungWajib() {
    const wajibKeywords = [
      'kelas', 'kerja', 'rapat', 'bimbingan', 'deadline', 'kuliah', 'riset',
    ];
    var n = 0;
    for (final list in _tasks.values) {
      for (final t in list) {
        final l = t.label.toLowerCase();
        if (wajibKeywords.any(l.contains)) n++;
      }
    }
    return n;
  }

  /// Lomba = aktivitas terkait lomba (label mengandung "lomba" atau warna
  /// accent lomba, termasuk persiapan/latihan/review/evaluasi lomba).
  static int _hitungLomba() {
    const lombaKeywords = [
      'lomba', 'latihan', 'persiapan', 'review', 'evaluasi',
    ];
    var n = 0;
    for (final list in _tasks.values) {
      for (final t in list) {
        final l = t.label.toLowerCase();
        if (lombaKeywords.any(l.contains)) n++;
      }
    }
    return n;
  }
}

/// Kotak ringkasan angka (ikon + nilai besar + label + hint).
class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.hint,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: C.bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: C.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              hint,
              style: const TextStyle(color: C.detailMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// Satu baris Gantt: grid guide + batang aktivitas terposisi via LayoutBuilder.
class _GanttRow extends StatelessWidget {
  const _GanttRow({required this.tasks});

  final List<_Task> tasks;

  static const int _startHour = JadwalRingkasanScreen._startHour;
  static const int _slots = JadwalRingkasanScreen._slots;
  static const double _rowHeight = 26;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final slotW = constraints.maxWidth / _slots;
        return SizedBox(
          height: _rowHeight,
          child: Stack(
            children: [
              // Grid guide lines
              Row(
                children: List.generate(
                  _slots,
                  (i) => Container(
                    width: slotW,
                    height: _rowHeight,
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: C.navInactive.withValues(alpha: 0.18),
                          width: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Task bars
              ...tasks.map((t) {
                final left = (t.start - _startHour) * slotW;
                final width = (t.end - t.start) * slotW;
                return Positioned(
                  left: left.clamp(0, constraints.maxWidth),
                  top: 4,
                  child: Container(
                    width: width.clamp(0, constraints.maxWidth - left),
                    height: _rowHeight - 8,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: t.color.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      t.label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: C.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
