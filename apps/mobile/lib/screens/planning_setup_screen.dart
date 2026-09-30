import 'package:flutter/material.dart';

import '../models/planning_input_draft.dart';
import '../models/planning_preferences.dart';
import '../models/recovery_policy.dart';
import '../theme/app_theme.dart';
import '../viewmodels/planning_host_view_model.dart';
import '../widgets/common.dart';
import '../widgets/recovery_panel.dart';

class PlanningSetupScreen extends StatefulWidget {
  const PlanningSetupScreen({
    super.key,
    required this.host,
    this.onBack,
    this.onDecisionReady,
  });

  final PlanningHostViewModel host;
  final VoidCallback? onBack;
  final VoidCallback? onDecisionReady;

  @override
  State<PlanningSetupScreen> createState() => _PlanningSetupScreenState();
}

class _PlanningSetupScreenState extends State<PlanningSetupScreen> {
  late final TextEditingController _age;
  late final TextEditingController _country;
  late final TextEditingController _scope;
  late final TextEditingController _timezone;
  late final TextEditingController _dailyLimit;
  late final TextEditingController _focus;
  late final TextEditingController _buffer;
  late final TextEditingController _startLocal;
  late final TextEditingController _endLocal;
  late List<PlanningTaskDraft> _tasks;
  bool? _studentStatus;
  bool _requireTech = false;
  String? _localError;

  PlanningDraft get _seed => widget.host.draft!;

  @override
  void initState() {
    super.initState();
    final draft = _seed;
    _age = TextEditingController(text: draft.readinessContext.age?.toString() ?? '');
    _country = TextEditingController(text: draft.readinessContext.country ?? '');
    _scope = TextEditingController(text: draft.readinessContext.selectedScope ?? '');
    _studentStatus = draft.readinessContext.studentStatus;
    _requireTech = draft.readinessContext.requireTechnologyInformation;
    _timezone = TextEditingController(text: draft.preferences.timezone);
    _dailyLimit = TextEditingController(
      text: draft.preferences.maxProjectMinutesPerDay.toString(),
    );
    _focus = TextEditingController(
      text: draft.preferences.preferredFocusMinutes.toString(),
    );
    _buffer = TextEditingController(
      text: draft.preferences.bufferTargetMinutes.toString(),
    );
    _startLocal = TextEditingController(text: draft.windowPolicy.startLocal);
    _endLocal = TextEditingController(text: draft.windowPolicy.endLocal);
    _tasks = [...draft.tasks];
  }

  @override
  void dispose() {
    for (final controller in [
      _age,
      _country,
      _scope,
      _timezone,
      _dailyLimit,
      _focus,
      _buffer,
      _startLocal,
      _endLocal,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _evaluate() async {
    FocusScope.of(context).unfocus();
    setState(() => _localError = null);
    try {
      final ageText = _age.text.trim();
      final age = ageText.isEmpty ? null : int.parse(ageText);
      if (age != null && age < 0) {
        throw const FormatException('Age must be zero or greater.');
      }
      final daily = int.parse(_dailyLimit.text.trim());
      final focus = int.parse(_focus.text.trim());
      final buffer = int.parse(_buffer.text.trim());
      if (daily < 0 || daily > 1440 || focus <= 0 || buffer < 0) {
        throw const FormatException(
          'Daily limit, focus duration, or buffer is outside its valid range.',
        );
      }
      final timezone = _timezone.text.trim();
      final policy = PlanningWindowPolicyV1(
        timezone: timezone,
        startMinutesOfDay: _clockMinutes(_startLocal.text),
        endMinutesOfDay: _clockMinutes(_endLocal.text),
      );
      final draft = PlanningDraft(
        readinessContext: ReadinessContextDraft(
          age: age,
          studentStatus: _studentStatus,
          country: _blank(_country.text),
          selectedScope: _blank(_scope.text),
          requireTechnologyInformation: _requireTech,
        ),
        tasks: _tasks,
        preferences: PlanningPreferences(
          timezone: timezone,
          maxProjectMinutesPerDay: daily,
          preferredFocusMinutes: focus,
          bufferTargetMinutes: buffer,
          updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
        ),
        windowPolicy: policy,
      );

      widget.host.commitDraft(draft);
      await widget.host.evaluate();
      if (!mounted) return;
      if (widget.host.phase == PlanningHostPhase.decision) {
        widget.onDecisionReady?.call();
      } else {
        setState(() {});
      }
    } on Object catch (error) {
      setState(() => _localError = _cleanError(error));
    }
  }

  Future<void> _retryPersistence() async {
    await widget.host.retryPersistence();
    if (!mounted) return;
    if (widget.host.phase == PlanningHostPhase.decision) {
      widget.onDecisionReady?.call();
    } else {
      setState(() {});
    }
  }

  Future<void> _retryRequest() async {
    await widget.host.retryRequest();
    if (!mounted) return;
    if (widget.host.phase == PlanningHostPhase.decision) {
      widget.onDecisionReady?.call();
    } else {
      setState(() {});
    }
  }

  Future<void> _discardPendingResult() async {
    if (!widget.host.canDiscardPendingResult) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: C.card,
            title: const Text('Discard unsaved evaluation?'),
            content: const Text(
              'This evaluation was not saved. Discarding it returns to the '
              'previous durable planning state and does not change an existing '
              'accepted plan.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep result'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Discard unsaved result'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    widget.host.discardPendingResult();
    setState(() {});
  }

  RecoveryDescriptor _failureDescriptor(PlanningHostFailure failure) {
    return RecoveryDescriptor(
      title: switch (failure.recoveryClass) {
        RecoveryClass.retrySameInput => 'Planning request can be retried',
        RecoveryClass.editConstraints => 'Planning inputs need attention',
        RecoveryClass.reloadContext => 'Planning context needs to be reloaded',
        RecoveryClass.reevaluate => 'A fresh evaluation baseline is required',
        _ => 'Planning could not complete safely',
      },
      message: failure.message,
      recoveryClass: failure.recoveryClass,
      technicalCode: failure.code,
      stage: failure.stage,
    );
  }

  Future<void> _addTask() async {
    final created = await _taskDialog();
    if (created != null && mounted) {
      setState(() => _tasks = [..._tasks, created]);
    }
  }

  Future<void> _editTask(PlanningTaskDraft task) async {
    final updated = await _taskDialog(existing: task);
    if (updated == null || !mounted) return;
    setState(() {
      final index = _tasks.indexWhere((item) => item.taskId == task.taskId);
      if (index >= 0) {
        final next = [..._tasks];
        next[index] = updated;
        _tasks = next;
      }
    });
  }

  Future<PlanningTaskDraft?> _taskDialog({
    PlanningTaskDraft? existing,
  }) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final min = TextEditingController(
      text: (existing?.effortMinMinutes ?? 60).toString(),
    );
    final likely = TextEditingController(
      text: (existing?.effortLikelyMinutes ?? 120).toString(),
    );
    final max = TextEditingController(
      text: (existing?.effortMaxMinutes ?? 180).toString(),
    );
    final dependencies = TextEditingController(
      text: existing?.dependencies.join(', ') ?? '',
    );
    final assumptions = TextEditingController(
      text: existing?.assumptions.join(', ') ?? '',
    );
    var mandatory = existing?.mandatory ?? true;
    String? error;

    final result = await showDialog<PlanningTaskDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: C.card,
          title: Text(existing == null ? 'Add planning task' : 'Edit planning task'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogField(controller: name, label: 'Task name'),
                _DialogField(
                  controller: min,
                  label: 'Minimum effort (minutes)',
                  numeric: true,
                ),
                _DialogField(
                  controller: likely,
                  label: 'Likely effort (minutes)',
                  numeric: true,
                ),
                _DialogField(
                  controller: max,
                  label: 'Maximum effort (minutes)',
                  numeric: true,
                ),
                _DialogField(
                  controller: dependencies,
                  label: 'Dependency task IDs (comma-separated)',
                ),
                _DialogField(
                  controller: assumptions,
                  label: 'Assumptions (comma-separated)',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mandatory'),
                  value: mandatory,
                  onChanged: (value) =>
                      setDialogState(() => mandatory = value),
                ),
                if (existing != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Stable ID: ${existing.taskId}',
                      style: const TextStyle(
                        color: C.detailMuted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: const TextStyle(color: C.padat),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final task = existing == null
                      ? PlanningTaskDraft.create(
                          name: name.text.trim(),
                          mandatory: mandatory,
                          effortMinMinutes: int.parse(min.text.trim()),
                          effortLikelyMinutes: int.parse(likely.text.trim()),
                          effortMaxMinutes: int.parse(max.text.trim()),
                          dependencies: _csv(dependencies.text),
                          assumptions: _csv(assumptions.text),
                        )
                      : existing.copyWith(
                          name: name.text.trim(),
                          mandatory: mandatory,
                          effortMinMinutes: int.parse(min.text.trim()),
                          effortLikelyMinutes: int.parse(likely.text.trim()),
                          effortMaxMinutes: int.parse(max.text.trim()),
                          dependencies: _csv(dependencies.text),
                          assumptions: _csv(assumptions.text),
                        );
                  Navigator.pop(dialogContext, task);
                } on Object catch (value) {
                  setDialogState(() => error = _cleanError(value));
                }
              },
              child: const Text('Save task'),
            ),
          ],
        ),
      ),
    );

    name.dispose();
    min.dispose();
    likely.dispose();
    max.dispose();
    dependencies.dispose();
    assumptions.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final busy = host.busy;
    final inputsLocked = host.inputsLocked;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeader(title: 'Planning Setup', onBack: widget.onBack),
          const HeaderDivider(),
          const SizedBox(height: 16),
          _Card(
            title: 'Readiness details',
            child: Column(
              children: [
                _Field(controller: _age, label: 'Age (optional)', numeric: true, enabled: !inputsLocked),
                DropdownButtonFormField<bool?>(
                  initialValue: _studentStatus,
                  decoration: const InputDecoration(labelText: 'Student status'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Unknown')),
                    DropdownMenuItem(value: true, child: Text('Student')),
                    DropdownMenuItem(value: false, child: Text('Not a student')),
                  ],
                  onChanged: inputsLocked
                      ? null
                      : (value) => setState(() => _studentStatus = value),
                ),
                _Field(controller: _country, label: 'Country (optional)', enabled: !inputsLocked),
                _Field(controller: _scope, label: 'Selected scope (optional)', enabled: !inputsLocked),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Require technology information'),
                  subtitle: const Text(
                    'Only enable this when technology requirements are relevant to your decision.',
                  ),
                  value: _requireTech,
                  onChanged: inputsLocked
                      ? null
                      : (value) => setState(() => _requireTech = value),
                ),
              ],
            ),
          ),
          _Card(
            title: 'Workload',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_tasks.isEmpty)
                  const Text(
                    'No authoritative workload yet. Add and confirm at least one task before evaluating.',
                    style: TextStyle(color: C.detailMuted),
                  ),
                for (final task in _tasks)
                  Material(
                    color: Colors.transparent,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(task.name),
                      subtitle: Text(
                        '${task.effortMinMinutes} / ${task.effortLikelyMinutes} / ${task.effortMaxMinutes} min\nID: ${task.taskId}',
                      ),
                      isThreeLine: true,
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'Edit task',
                            onPressed:
                                inputsLocked ? null : () => _editTask(task),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Delete task',
                            onPressed: inputsLocked
                                ? null
                                : () => setState(() {
                                      _tasks = _tasks
                                          .where((item) =>
                                              item.taskId != task.taskId)
                                          .toList(growable: false);
                                    }),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: inputsLocked ? null : _addTask,
                  icon: const Icon(Icons.add),
                  label: const Text('Add task'),
                ),
              ],
            ),
          ),
          _Card(
            title: 'Planning constraints',
            child: Column(
              children: [
                _Field(controller: _timezone, label: 'IANA timezone', enabled: !inputsLocked),
                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        controller: _startLocal,
                        label: 'Planning hours start',
                        hint: '08:00',
                        enabled: !inputsLocked,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Field(
                        controller: _endLocal,
                        label: 'Planning hours end',
                        hint: '22:00',
                        enabled: !inputsLocked,
                      ),
                    ),
                  ],
                ),
                _Field(
                  controller: _dailyLimit,
                  label: 'Daily project limit (minutes)',
                  numeric: true,
                  enabled: !inputsLocked,
                ),
                _Field(
                  controller: _focus,
                  label: 'Preferred focus duration (minutes)',
                  numeric: true,
                  enabled: !inputsLocked,
                ),
                _Field(
                  controller: _buffer,
                  label: 'Buffer target (minutes)',
                  numeric: true,
                  enabled: !inputsLocked,
                ),
                if (host.hasAcceptedPlan)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: inputsLocked
                          ? null
                          : () async {
                              await host.useCurrentDefaults();
                              if (!mounted) return;
                              final next = host.draft!;
                              setState(() {
                                _timezone.text = next.preferences.timezone;
                                _dailyLimit.text = next
                                    .preferences.maxProjectMinutesPerDay
                                    .toString();
                                _focus.text = next
                                    .preferences.preferredFocusMinutes
                                    .toString();
                                _buffer.text = next
                                    .preferences.bufferTargetMinutes
                                    .toString();
                              });
                            },
                      child: const Text('Use current global defaults'),
                    ),
                  ),
              ],
            ),
          ),
          if (_localError != null)
            _ErrorBox(text: _localError!),
          if (host.failure != null) ...[
            RecoveryPanel(
              descriptor: host.canRetryPersistence
                  ? RecoveryDescriptor(
                      title: host.hasKnownUnpersistedStaleWitness
                          ? 'Trusted stale state still needs saving'
                          : 'Evaluation result is not saved yet',
                      message: host.failure!.message,
                      recoveryClass: RecoveryClass.noAutomaticRecovery,
                      technicalCode: host.failure!.code,
                      stage: host.failure!.stage,
                    )
                  : _failureDescriptor(host.failure!),
              primaryLabel: host.canRetryPersistence
                  ? 'Retry local save'
                  : host.canRetryRequest
                      ? 'Retry request'
                      : null,
              onPrimary: host.canRetryPersistence
                  ? _retryPersistence
                  : host.canRetryRequest
                      ? _retryRequest
                      : null,
              secondaryLabel: host.canDiscardPendingResult
                  ? 'Discard unsaved result'
                  : null,
              onSecondary:
                  host.canDiscardPendingResult ? _discardPendingResult : null,
            ),
            const SizedBox(height: 12),
          ],
          if (host.message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                host.message!,
                style: const TextStyle(color: C.accent),
              ),
            ),
          if (!host.canRetryPersistence && !host.canRetryRequest)
            FilledButton(
              onPressed: busy ? null : _evaluate,
              child: Text(
                busy
                    ? 'Evaluating…'
                    : host.hasAcceptedPlan
                        ? 'Re-evaluate plan'
                        : 'Evaluate',
              ),
            ),
          if (host.canCreateFreshBaseline)
            TextButton(
              onPressed: () {
                host.createFreshEvaluationBaseline();
                setState(() {});
              },
              child: const Text('Create fresh evaluation baseline'),
            ),
          if (host.phase == PlanningHostPhase.unchanged)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'No material planning changes were found. Your accepted plan remains current.',
                textAlign: TextAlign.center,
                style: TextStyle(color: C.detailMuted),
              ),
            ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Material(
          color: C.card,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                child,
              ],
            ),
          ),
        ),
      );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.numeric = false,
    this.hint,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final bool numeric;
  final String? hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );
}

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.controller,
    required this.label,
    this.numeric = false,
  });

  final TextEditingController controller;
  final String label;
  final bool numeric;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: controller,
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(labelText: label),
        ),
      );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: C.padat),
        ),
        child: Text(text),
      );
}

String? _blank(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _csv(String value) => value
    .split(',')
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toList(growable: false);

int _clockMinutes(String value) {
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value.trim());
  if (match == null) {
    throw const FormatException('Planning hours must use HH:mm.');
  }
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) {
    throw const FormatException('Planning hours contain an invalid time.');
  }
  return hour * 60 + minute;
}

String _cleanError(Object error) {
  final text = error.toString();
  return text
      .replaceFirst('FormatException: ', '')
      .replaceFirst('Invalid argument(s): ', '');
}
