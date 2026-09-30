import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/active_accepted_block.dart';
import '../models/commitment.dart';
import '../models/schedule_occurrence.dart';
import '../theme/app_theme.dart';
import '../viewmodels/jadwal_view_model.dart';
import '../widgets/common.dart';

class JadwalTabs extends StatelessWidget {
  const JadwalTabs({
    super.key,
    required this.activeIndex,
    required this.onChanged,
  });

  final int activeIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, int index) {
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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          tab('Daily Schedule', 0),
          const SizedBox(width: 4),
          tab('Weekly Summary', 1),
        ],
      ),
    );
  }
}

class JadwalHarianScreen extends StatelessWidget {
  const JadwalHarianScreen({
    super.key,
    required this.onSwitchTab,
    this.onAdd,
    this.onBack,
    this.onEdit,
    this.onOpenSavedPlan,
  });

  final ValueChanged<int> onSwitchTab;
  final VoidCallback? onAdd;
  final VoidCallback? onBack;
  final ValueChanged<Commitment>? onEdit;
  final ValueChanged<String>? onOpenSavedPlan;

  static const _dayHeaders = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  static Color _dotFor(Commitment commitment) {
    return switch (commitment.category?.toLowerCase()) {
      'kuliah' => C.dotBlue,
      'lomba' => C.accent,
      'tim' => C.dotPurple,
      _ => C.dotGreen,
    };
  }

  static String _hhmm(DateTime time) =>
      "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";

  static String _duration(int minutes) {
    if (minutes % 60 == 0) return '${minutes ~/ 60} hr';
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} hr ${minutes % 60} min';
  }

  static List<List<int?>> _weeks(DateTime month) {
    final count = DateTime(month.year, month.month + 1, 0).day;
    final offset = DateTime(month.year, month.month, 1).weekday - 1;
    final cells = <int?>[
      ...List<int?>.filled(offset, null),
      ...List<int?>.generate(count, (index) => index + 1),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return [
      for (var index = 0; index < cells.length; index += 7)
        cells.sublist(index, index + 7),
    ];
  }

  Future<void> _delete(
    BuildContext context,
    JadwalViewModel vm,
    ScheduleOccurrence item,
  ) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: C.card,
            title: const Text('Delete schedule?'),
            content: Text(
              item.isRecurring
                  ? 'This will delete the entire recurring schedule.'
                  : 'This schedule will be deleted from this device.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    final ok = await vm.hapus(item.commitment.id);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(vm.errorMessage ?? 'Failed to delete schedule')),
      );
    }
  }

  Future<void> _cancel(
    BuildContext context,
    JadwalViewModel vm,
    ScheduleOccurrence item,
  ) async {
    final ok = await vm.cancelOccurrence(item);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'This occurrence was canceled. The recurring series remains.'
              : (vm.errorMessage ?? 'Failed to save changes'),
        ),
      ),
    );
  }

  Future<void> _move(
    BuildContext context,
    JadwalViewModel vm,
    ScheduleOccurrence item,
  ) async {
    final date = await showDatePicker(
      context: context,
      initialDate: item.startAt,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (date == null || !context.mounted) return;
    final start = DateTime(
      date.year,
      date.month,
      date.day,
      item.startAt.hour,
      item.startAt.minute,
    );
    final end = start.add(Duration(minutes: item.durationMinutes));
    final ok = await vm.moveOccurrence(item, start, end);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'This occurrence was moved without changing the recurring pattern.'
              : (vm.errorMessage ?? 'Failed to save changes'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<JadwalViewModel>();
    final selected = vm.selectedDate;
    final items = vm.itemsForSelectedDate;
    final acceptedItems = vm.acceptedItemsForSelectedDate;
    final eventDays = vm.eventDaysOfMonth(selected);
    final header =
        '${_dayNames[selected.weekday - 1]}, ${selected.day} ${_monthNames[selected.month - 1]}';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeader(
            title: 'My Schedule',
            trailing: AddButton(onTap: vm.isSaving ? null : onAdd),
            onBack: onBack,
          ),
          const HeaderDivider(),
          if (vm.isLoading) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 16),
          JadwalTabs(activeIndex: 0, onChanged: onSwitchTab),
          const SizedBox(height: 16),
          HorizontalSwipeSurface(
            key: const Key('month-calendar-swipe-area'),
            behavior: HitTestBehavior.opaque,
            onSwipeLeft: () => vm.selectDate(
              DateTime(selected.year, selected.month + 1, 1),
            ),
            onSwipeRight: () => vm.selectDate(
              DateTime(selected.year, selected.month - 1, 1),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: C.accent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => vm.selectDate(
                          DateTime(selected.year, selected.month - 1, 1),
                        ),
                        child: const Icon(Icons.chevron_left, color: C.bg),
                      ),
                      Text(
                        '${_monthNames[selected.month - 1]} ${selected.year}',
                        key: const Key('calendar-month-label'),
                        style: const TextStyle(
                          color: C.bg,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => vm.selectDate(
                          DateTime(selected.year, selected.month + 1, 1),
                        ),
                        child: const Icon(Icons.chevron_right, color: C.bg),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: C.cardAlt,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          for (final day in _dayHeaders)
                            Expanded(
                              child: Center(
                                child: Text(
                                  day,
                                  style: const TextStyle(
                                    color: C.dayHeader,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final week in _weeks(selected))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              for (final day in week)
                                Expanded(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: day == null
                                        ? null
                                        : () => vm.selectDay(
                                              day,
                                              inMonth: selected,
                                            ),
                                    child: Container(
                                      height: 44,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: day == selected.day
                                            ? C.accent
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            day?.toString() ?? '',
                                            style: TextStyle(
                                              color: day == selected.day
                                                  ? C.bg
                                                  : C.white,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            width: 5,
                                            height: 5,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: day != null &&
                                                      eventDays.contains(day)
                                                  ? (day == selected.day
                                                      ? C.bg
                                                      : C.accent)
                                                  : Colors.transparent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionHeading(title: header),
          const SizedBox(height: 16),
          if (vm.errorMessage != null && !vm.isLoading)
            _RetryCard(message: vm.errorMessage!, onRetry: vm.retry)
          else if (vm.isLoading)
            const Center(child: CircularProgressIndicator(color: C.accent))
          else if (items.isEmpty && acceptedItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: PresentationCard(
                child: Column(
                  key: const Key('schedule-empty-state'),
                  children: [
                    const Icon(
                      Icons.event_available_outlined,
                      color: C.accent,
                      size: 30,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'No schedule for this date',
                      style: TextStyle(
                        color: C.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Add a commitment or import a calendar from the Add Schedule flow.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: C.detailMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    if (onAdd != null) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: const Key('empty-add-schedule'),
                        onPressed: onAdd,
                        icon: const Icon(Icons.add),
                        label: const Text('Add schedule'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else ...[
            for (final item in items) ...[
              _ActivityCard(
                item: item,
                dot: _dotFor(item.commitment),
                time: _hhmm(item.startAt),
                duration: _duration(item.durationMinutes),
                onEdit: () => onEdit?.call(item.commitment),
                onDelete: () => _delete(context, vm, item),
                onCancel: item.isRecurring
                    ? () => _cancel(context, vm, item)
                    : null,
                onMove: item.isRecurring
                    ? () => _move(context, vm, item)
                    : null,
              ),
              const SizedBox(height: 16),
            ],
            for (final block in acceptedItems) ...[
              _AcceptedPlanCard(
                block: block,
                time: _hhmm(block.startAt),
                duration: _duration(block.durationMinutes),
                onTap: () => onOpenSavedPlan?.call(block.savedPlanId),
              ),
              const SizedBox(height: 16),
            ],
          ],
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: C.accent, size: 18),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your calendar will not be changed automatically. Takt only reads the capacity you confirm.',
                    style: TextStyle(color: C.detailMuted, fontSize: 12),
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

class _AcceptedPlanCard extends StatelessWidget {
  const _AcceptedPlanCard({
    required this.block,
    required this.time,
    required this.duration,
    required this.onTap,
  });

  final ActiveAcceptedBlock block;
  final String time;
  final String duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: C.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: C.accent,
                    shape: BoxShape.circle,
                  ),
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
                        block.taskName,
                        style: const TextStyle(
                          color: C.white,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$duration · accepted plan · read only',
                        style: const TextStyle(
                          color: C.detailMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: C.accent,
                ),
              ],
            ),
          ),
        ),
      );
}

class _RetryCard extends StatelessWidget {
  const _RetryCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

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
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: C.detailMuted, fontSize: 13),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.item,
    required this.dot,
    required this.time,
    required this.duration,
    this.onEdit,
    this.onDelete,
    this.onCancel,
    this.onMove,
  });

  final ScheduleOccurrence item;
  final Color dot;
  final String time;
  final String duration;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onCancel;
  final VoidCallback? onMove;

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
                  item.commitment.title,
                  style: const TextStyle(color: C.white, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    duration,
                    item.commitment.type == CommitmentType.fixed
                        ? 'fixed time'
                        : 'flexible label · still blocks this time',
                    if (item.isRecurring) 'recurring',
                    if (item.startAtEpochMs != item.originalStartAtEpochMs)
                      'moved occurrence',
                  ].join(' · '),
                  key: Key('occurrence-meta-${item.commitment.id}'),
                  style: const TextStyle(
                    color: C.detailMuted,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (item.isRecurring)
            PopupMenuButton<String>(
              color: C.card,
              icon: const Icon(
                Icons.more_horiz,
                color: C.detailMuted,
                size: 19,
              ),
              onSelected: (value) {
                if (value == 'move') onMove?.call();
                if (value == 'cancel') onCancel?.call();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'move',
                  child: Text('Move this occurrence'),
                ),
                PopupMenuItem(
                  value: 'cancel',
                  child: Text('Cancel this occurrence'),
                ),
              ],
            ),
          IconButton(
            tooltip: 'Edit schedule',
            onPressed: onEdit,
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.edit_outlined,
              color: C.detailMuted,
              size: 18,
            ),
          ),
          IconButton(
            tooltip: 'Delete schedule',
            onPressed: onDelete,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, color: C.detailMuted, size: 18),
          ),
        ],
      ),
    );
  }
}