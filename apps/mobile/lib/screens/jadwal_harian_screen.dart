import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Tab switcher Jadwal Harian / Ringkasan Pekan (dipakai di kedua screen jadwal).
class JadwalTabs extends StatelessWidget {
  const JadwalTabs({super.key, required this.activeIndex, required this.onChanged});

  final int activeIndex; // 0 = harian, 1 = ringkasan
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _tab('Jadwal Harian', 0),
          const SizedBox(width: 4),
          _tab('Ringkasan Pekan', 1),
        ],
      ),
    );
  }

  Widget _tab(String label, int index) {
    final active = index == activeIndex;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? C.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: active ? C.bg : C.navInactive,
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// JadwalHarianScreen — Figma node 11:1331 (tab Jadwal Harian).
class JadwalHarianScreen extends StatelessWidget {
  const JadwalHarianScreen({super.key, required this.onSwitchTab});

  final ValueChanged<int> onSwitchTab;

  static const _dayHeaders = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
  static const _firstOffset = 1; // 1 Sept 2026 = Selasa
  static const _daysInMonth = 30;
  static const _selectedDay = 27;
  static const _eventDays = [21, 22, 23, 24, 25, 26, 27];

  static const _activities = <_Activity>[
    _Activity('07:00', 'Sarapan & Persiapan', '1 jam', C.dotGreen),
    _Activity('08:00', 'Kuliah Pagi — Algoritma', '2 jam', C.dotBlue),
    _Activity('10:00', 'Review Proposal Hackathon', '1.5 jam', C.accent),
    _Activity('12:00', 'Istirahat & Makan Siang', '1 jam', C.dotGreen),
    _Activity('13:00', 'Riset Kompetisi AI', '2 jam', C.accent),
    _Activity('15:00', 'Rapat Tim — Prototipe', '1.5 jam', C.dotPurple),
    _Activity('17:00', 'Cadangan / Waktu Luang', 'Fleksibel', C.dotGray),
  ];

  List<List<int?>> _weeks() {
    final cells = <int?>[
      ...List<int?>.filled(_firstOffset, null),
      ...List<int?>.generate(_daysInMonth, (i) => i + 1),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final weeks = <List<int?>>[];
    for (var i = 0; i < cells.length; i += 7) {
      weeks.add(cells.sublist(i, i + 7));
    }
    return weeks;
  }

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

          JadwalTabs(activeIndex: 0, onChanged: onSwitchTab),
          const SizedBox(height: 16),

          // Month selector
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: C.accent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Icon(Icons.chevron_left, color: C.bg, size: 22),
                Text(
                  'September 2026',
                  style: TextStyle(
                    color: C.bg,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Icon(Icons.chevron_right, color: C.bg, size: 22),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Calendar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            decoration: BoxDecoration(
              color: C.cardAlt,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  children: _dayHeaders
                      .map((d) => Expanded(
                            child: Center(
                              child: Text(
                                d,
                                style: const TextStyle(
                                  color: C.dayHeader,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                ..._weeks().map(
                  (week) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: week.map((day) {
                        final selected = day == _selectedDay;
                        final hasEvent =
                            day != null && _eventDays.contains(day);
                        return Expanded(
                          child: Container(
                            height: 44,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: selected ? C.accent : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  day?.toString() ?? '',
                                  style: TextStyle(
                                    color: selected ? C.bg : C.white,
                                    fontSize: 14,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: hasEvent
                                        ? (selected ? C.bg : C.accent)
                                        : Colors.transparent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          const SectionHeading(
              title: 'Sabtu, 27 September', action: 'Tambah'),
          const SizedBox(height: 16),

          // Activity timeline
          ..._activities.expand((a) => [
                _ActivityCard(activity: a),
                const SizedBox(height: 16),
              ]),

          // Info note
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
                  child: const Icon(Icons.info_outline,
                      color: C.accent, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Kalender tidak akan diubah otomatis',
                        style: TextStyle(color: C.white, fontSize: 14),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Timbang hanya membaca kapasitas yang Anda konfirmasi',
                        style: TextStyle(color: C.detailMuted, fontSize: 12),
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

class _Activity {
  const _Activity(this.time, this.title, this.duration, this.dot);
  final String time;
  final String title;
  final String duration;
  final Color dot;
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.activity});
  final _Activity activity;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: activity.dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 44,
            child: Text(
              activity.time,
              style: const TextStyle(
                color: C.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.title,
                  style: const TextStyle(color: C.white, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  activity.duration,
                  style: const TextStyle(color: C.detailMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
