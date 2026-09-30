import 'package:flutter/material.dart';

import '../data/repositories/saved_plan_repository.dart';
import '../theme/app_theme.dart';
import '../viewmodels/saved_plan_detail_view_model.dart';
import '../widgets/common.dart';

class SavedPlanDetailScreen extends StatefulWidget {
  const SavedPlanDetailScreen({
    super.key,
    required this.savedPlanId,
    required this.viewModel,
    this.onBack,
    this.onReevaluate,
    this.onViewSchedule,
  });

  final String savedPlanId;
  final SavedPlanDetailViewModel viewModel;
  final VoidCallback? onBack;
  final ValueChanged<SavedPlanSummary>? onReevaluate;
  final ValueChanged<SavedPlanSummary>? onViewSchedule;

  @override
  State<SavedPlanDetailScreen> createState() =>
      _SavedPlanDetailScreenState();
}

class _SavedPlanDetailScreenState extends State<SavedPlanDetailScreen> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_changed);
    widget.viewModel.load(widget.savedPlanId);
  }

  @override
  void didUpdateWidget(covariant SavedPlanDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.removeListener(_changed);
      widget.viewModel.addListener(_changed);
    }
    if (oldWidget.savedPlanId != widget.savedPlanId) {
      widget.viewModel.load(widget.savedPlanId);
    }
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _editProgress(SavedPlanTaskState state) async {
    final progress = TextEditingController(
      text: state.progress.progressPercent.toString(),
    );
    final actual = TextEditingController(
      text: state.progress.actualMinutes?.toString() ?? '',
    );
    var clearActual = false;
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: C.card,
          title: Text(state.task.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: progress,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Progress percent (0–100)',
                ),
              ),
              TextField(
                controller: actual,
                enabled: !clearActual,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Actual effort minutes (optional)',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Clear actual effort'),
                value: clearActual,
                onChanged: (value) => setDialogState(
                  () => clearActual = value ?? false,
                ),
              ),
              if (error != null)
                Text(error!, style: const TextStyle(color: C.padat)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final progressValue = int.parse(progress.text.trim());
                  final actualText = actual.text.trim();
                  final actualValue = actualText.isEmpty
                      ? null
                      : int.parse(actualText);
                  final ok = await widget.viewModel.updateProgress(
                    savedPlanTaskId: state.task.id,
                    progressPercent: progressValue,
                    actualMinutes: actualValue,
                    clearActualMinutes: clearActual,
                  );
                  if (!dialogContext.mounted) return;
                  if (ok) {
                    Navigator.pop(dialogContext, true);
                  } else {
                    setDialogState(
                      () => error = widget.viewModel.error ??
                          'Progress could not be saved.',
                    );
                  }
                } on Object {
                  setDialogState(
                    () => error = 'Enter valid non-negative numeric values.',
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    progress.dispose();
    actual.dispose();
    if (saved == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final detail = vm.detail;

    if (vm.loading && detail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (detail == null) {
      return Column(
        children: [
          AppHeader(title: 'Saved Plan', onBack: widget.onBack),
          const HeaderDivider(),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(vm.error ?? 'Saved plan is unavailable.'),
          ),
        ],
      );
    }

    final summary = detail.summary;
    return Column(
      children: [
        AppHeader(title: 'Saved Plan', onBack: widget.onBack),
        const HeaderDivider(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            summary.title,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        StatusPill(
                          label: summary.stale ? 'SUPERSEDED' : 'CURRENT',
                          color: summary.stale ? C.padat : C.kosong,
                          icon: summary.stale
                              ? Icons.history_toggle_off_rounded
                              : Icons.check_circle_outline_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Accepted plan · persisted user decision',
                      key: Key('accepted-plan-label'),
                      style: TextStyle(
                        color: C.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Revision ${summary.currentRevision.revisionNumber} · '
                      '${summary.currentRevision.selectedCandidateId}',
                      style: const TextStyle(color: C.detailMuted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Accepted ${_instant(summary.currentRevision.acceptedAt)}',
                      style: const TextStyle(color: C.detailMuted),
                    ),
                    if (summary.stale) ...[
                      const SizedBox(height: 12),
                      PresentationCard(
                        highlightColor: C.padat,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Persisted evaluation stale',
                              key: Key('persisted-evaluation-stale'),
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'A trusted SUPERSEDED transition established that the source evaluation is no longer current. This accepted revision remains in history and is not rewritten.',
                              style: TextStyle(color: C.detailMuted, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: () => widget.onReevaluate?.call(summary),
                      child: const Text('Re-evaluate'),
                    ),
                    OutlinedButton(
                      onPressed: () => widget.onViewSchedule?.call(summary),
                      child: const Text('View Schedule'),
                    ),
                  ],
                ),
              ),
              const _SectionTitle('Tasks and progress'),
              if (detail.tasks.isEmpty)
                const _Card(
                  child: Text('No task snapshot is available.'),
                ),
              for (final state in detail.tasks)
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        state.task.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Expected ${state.task.effortMinMinutes} / '
                        '${state.task.effortLikelyMinutes} / '
                        '${state.task.effortMaxMinutes} min',
                        style: const TextStyle(color: C.detailMuted),
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: state.progress.progressPercent / 100,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${state.progress.progressPercent}% · actual '
                        '${state.progress.actualMinutes?.toString() ?? 'not recorded'} min',
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: vm.saving
                              ? null
                              : () => _editProgress(state),
                          child: const Text('Update progress'),
                        ),
                      ),
                    ],
                  ),
                ),
              const _SectionTitle('Accepted schedule'),
              if (detail.acceptedCommitments.isEmpty)
                const _Card(
                  child: Text('This revision contains no accepted work blocks.'),
                ),
              for (final block in detail.acceptedCommitments)
                _Card(
                  child: Text(
                    '${_instant(block.startAt)} → ${_instant(block.endAt)}\n'
                    '${block.allocatedMinutes} min · '
                    '${block.originalAvailabilitySource}',
                  ),
                ),
              const _SectionTitle('Revision history'),
              for (final revision in detail.revisions)
                _Card(
                  child: Text(
                    'Revision ${revision.revisionNumber} · '
                    '${revision.selectedCandidateId}\n'
                    'Accepted ${_instant(revision.acceptedAt)}',
                  ),
                ),
              if (vm.error != null)
                Text(
                  vm.error!,
                  style: const TextStyle(color: C.padat),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

String _instant(DateTime value) {
  final local = value.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
