import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/commitment.dart';
import '../theme/app_theme.dart';
import '../viewmodels/jadwal_view_model.dart';
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
/// Kini berbasis data: kalender bisa diklik, daftar aktivitas mengikuti
/// tanggal terpilih dari [JadwalViewModel].
class JadwalHarianScreen extends StatelessWidget {
  const JadwalHarianScreen({
    super.key,
    required this.onSwitchTab,
    this.onAdd,
    this.onBack,
  });

  final ValueChanged<int> onSwitchTab;
  final VoidCallback? onAdd;
  final VoidCallback? onBack;

  static const _dayHeaders = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
  static const _monthNames = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];
  static const _dayNames = [
    'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu',
  ];

  /// Warna dot aktivitas — dari kategori komitmen (konsisten & deterministik).
  static Color _dotFor(Commitment c) {
    switch (c.category) {
      case 'Kuliah':
        return C.dotBlue;
      case 'Lomba':
        return C.accent;
      case 'Tim':
        return C.dotPurple;
      default:
        return C.dotGreen;
    }
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _durasi(int menit) {
    if (menit % 60 == 0) return '${menit ~/ 60} jam';
    if (menit < 60) return '$menit menit';
    final j = menit ~/ 60;
    final m = menit % 60;
    return '$j jam $m menit';
  }

  /// Susun kotak-kotak kalender untuk [month]. Kolom pertama = Senin.
  List<List<int?>> _weeks(DateTime month) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // weekday: Senin=1 .. Minggu=7 → offset 0..6
    final firstOffset = DateTime(month.year, month.month, 1).weekday - 1;
    final cells = <int?>[
      ...List<int?>.filled(firstOffset, null),
      ...List<int?>.generate(daysInMonth, (i) => i + 1),
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
    final vm = context.watch<JadwalViewModel>();
    final selected = vm.selectedDate;
    final eventDays = vm.eventDaysOfMonth(selected);
    final items = vm.itemsForSelectedDate;
    final headerTanggal =
        '${_dayNames[selected.weekday - 1]}, ${selected.day} ${_monthNames[selected.month - 1]}';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeader(
            title: 'Jadwal Saya',
            trailing: AddButton(onTap: onAdd),
            onBack: onBack,
          ),
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
              children: [
                GestureDetector(
                  onTap: () => vm.selectDate(
                      DateTime(selected.year, selected.month - 1, 1)),
                  child: const Icon(Icons.chevron_left, color: C.bg, size: 22),
                ),
                Text(
                  '${_monthNames[selected.month - 1]} ${selected.year}',
                  style: const TextStyle(
                    color: C.bg,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                GestureDetector(
                  onTap: () => vm.selectDate(
                      DateTime(selected.year, selected.month + 1, 1)),
                  child: const Icon(Icons.chevron_right, color: C.bg, size: 22),
                ),
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
                ..._weeks(selected).map(
                  (week) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: week.map((day) {
                        final isSelected = day == selected.day;
                        final hasEvent =
                            day != null && eventDays.contains(day);
                        return Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: day == null
                                ? null
                                : () => vm.selectDay(day, inMonth: selected),
                            child: Container(
                              height: 44,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? C.accent
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    day?.toString() ?? '',
                                    style: TextStyle(
                                      color: isSelected ? C.bg : C.white,
                                      fontSize: 14,
                                      fontWeight: isSelected
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
                                          ? (isSelected ? C.bg : C.accent)
                                          : Colors.transparent,
                                    ),
                                  ),
                                ],
                              ),
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

          SectionHeading(title: headerTanggal),
          const SizedBox(height: 16),

          // Activity timeline — dari data tanggal terpilih
          if (items.isEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                color: C.card,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Belum ada jadwal di tanggal ini',
                style: TextStyle(color: C.detailMuted, fontSize: 13),
              ),
            )
          else
            ...items.expand((c) => [
                  _ActivityCard(
                    time: _hhmm(c.startAt),
                    title: c.title,
                    duration: _durasi(c.durationMinutes),
                    dot: _dotFor(c),
                    onDelete: () => vm.hapus(c.id),
                  ),
                  const SizedBox(height: 16),
                ]),
          const SizedBox(height: 0),

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

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.time,
    required this.title,
    required this.duration,
    required this.dot,
    this.onDelete,
  });

  final String time;
  final String title;
  final String duration;
  final Color dot;
  final VoidCallback? onDelete;

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
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 44,
            child: Text(
              time,
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
                  title,
                  style: const TextStyle(color: C.white, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  duration,
                  style: const TextStyle(color: C.detailMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (onDelete != null)
            GestureDetector(
              onTap: onDelete,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.close, color: C.detailMuted, size: 18),
              ),
            ),
        ],
      ),
    );
  }
}
