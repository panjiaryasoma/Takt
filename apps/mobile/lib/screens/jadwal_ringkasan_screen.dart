import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/active_accepted_block.dart';
import '../models/enums.dart';
import '../models/schedule_occurrence.dart';
import '../theme/app_theme.dart';
import '../viewmodels/jadwal_view_model.dart';
import '../widgets/common.dart';
import 'jadwal_harian_screen.dart' show JadwalTabs;

class _Task {
  const _Task(this.label, this.start, this.end, this.color);

  final String label;
  final double start;
  final double end;
  final Color color;
}

class JadwalRingkasanScreen extends StatelessWidget {
  const JadwalRingkasanScreen({super.key, required this.onSwitchTab});

  final ValueChanged<int> onSwitchTab;

  static const int _startHour = 7;
  static const int _endHour = 22;
  static const int _slots = _endHour - _startHour;
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static Color _colorFor(ScheduleOccurrence item) {
    if (item.commitment.source.startsWith('lomba:')) return C.accent;
    switch (item.commitment.category?.toLowerCase()) {
      case 'kuliah':
        return C.dotBlue;
      case 'tim':
        return C.dotPurple;
      case 'lomba':
        return C.accent;
      default:
        return item.commitment.type == CommitmentType.fixed
            ? C.sibuk
            : C.dotGreen;
    }
  }

  static Map<String, List<_Task>> _tasksForWeek(
    List<ScheduleOccurrence> occurrences,
    List<ActiveAcceptedBlock> acceptedBlocks,
  ) {
    final result = <String, List<_Task>>{
      for (final day in _days) day: <_Task>[],
    };
    for (final occurrence in occurrences) {
      final start = occurrence.startAt;
      final end = occurrence.endAt;
      final startHour = start.hour + start.minute / 60.0;
      final endHour = end.hour + end.minute / 60.0;
      result[_days[start.weekday - 1]]!.add(
        _Task(
          occurrence.commitment.title,
          startHour,
          endHour,
          _colorFor(occurrence),
        ),
      );
    }
    for (final block in acceptedBlocks) {
      final start = block.startAt;
      final end = block.endAt;
      final startHour = start.hour + start.minute / 60.0;
      final endHour = end.hour + end.minute / 60.0;
      result[_days[start.weekday - 1]]!.add(
        _Task(
          block.taskName,
          startHour,
          endHour,
          C.accent,
        ),
      );
    }
    for (final tasks in result.values) {
      tasks.sort((a, b) => a.start.compareTo(b.start));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<JadwalViewModel>();
    final selected = vm.selectedDate;
    final monday = DateTime(selected.year, selected.month, selected.day)
        .subtract(Duration(days: selected.weekday - 1));
    final nextMonday = monday.add(const Duration(days: 7));
    final occurrences = vm.occurrencesBetween(monday, nextMonday);
    final acceptedBlocks = vm.acceptedBlocksBetween(monday, nextMonday);
    final tasks = _tasksForWeek(occurrences, acceptedBlocks);
    final fixedCount = occurrences
        .where((item) => item.commitment.type == CommitmentType.fixed)
        .length;
    final competitionCount = occurrences
            .where((item) => item.commitment.source.startsWith('lomba:'))
            .length +
        acceptedBlocks.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppHeader(title: 'My Schedule'),
          const HeaderDivider(),
          if (vm.isLoading) const LinearProgressIndicator(minHeight: 2),
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
                  'This Week Gantt Chart',
                  style: TextStyle(
                    color: C.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                const Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    _Legend(color: C.dotBlue, label: 'Class'),
                    _Legend(color: C.dotPurple, label: 'Team'),
                    _Legend(color: C.sibuk, label: 'Fixed'),
                    _Legend(color: C.dotGreen, label: 'Flexible'),
                    _Legend(color: C.accent, label: 'Competition'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const SizedBox(width: 30),
                    ...List.generate(_slots, (index) {
                      final hour = _startHour + index;
                      return Expanded(
                        child: Center(
                          child: Text(
                            hour.toString().padLeft(2, '0'),
                            style: const TextStyle(
                              color: C.navInactive,
                              fontSize: 8,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 4),
                ..._days.map(
                  (day) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 30,
                          child: Text(
                            day,
                            style: TextStyle(
                              color: day == 'Sat' ? C.accent : C.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Expanded(child: _GanttRow(tasks: tasks[day] ?? const [])),
                      ],
                    ),
                  ),
                ),
                if (occurrences.isEmpty && acceptedBlocks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'No schedule for this week.',
                      style: TextStyle(color: C.detailMuted, fontSize: 11),
                    ),
                  ),
              ],
            ),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Weekly Summary',
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
                      icon: Icons.lock_clock_outlined,
                      color: C.dotBlue,
                      value: '$fixedCount',
                      label: 'Fixed schedules',
                      hint: 'Time blocks that cannot be moved',
                    ),
                    const SizedBox(width: 12),
                    _SummaryTile(
                      icon: Icons.emoji_events_rounded,
                      color: C.accent,
                      value: '$competitionCount',
                      label: 'Competition',
                      hint: 'Competition commitments this week',
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
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(color: C.navInactive, fontSize: 9),
        ),
      ],
    );
  }
}

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
        final slotWidth = constraints.maxWidth / _slots;
        return SizedBox(
          height: _rowHeight,
          child: Stack(
            children: [
              Row(
                children: List.generate(
                  _slots,
                  (index) => Container(
                    width: slotWidth,
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
              ...tasks.map((task) {
                final visibleStart = task.start.clamp(
                  _startHour.toDouble(),
                  (_startHour + _slots).toDouble(),
                ).toDouble();
                final visibleEnd = task.end.clamp(
                  _startHour.toDouble(),
                  (_startHour + _slots).toDouble(),
                ).toDouble();
                if (visibleEnd <= visibleStart) return const SizedBox.shrink();
                final left = (visibleStart - _startHour) * slotWidth;
                final width = (visibleEnd - visibleStart) * slotWidth;
                return Positioned(
                  left: left,
                  top: 4,
                  child: Container(
                    width: width,
                    height: _rowHeight - 8,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: task.color.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      task.label,
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