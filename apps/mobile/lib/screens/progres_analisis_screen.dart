import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/analysis_failure.dart';
import '../models/analysis_step.dart';
import '../models/recovery_policy.dart';
import '../theme/app_theme.dart';
import '../viewmodels/analisis_view_model.dart';
import '../widgets/common.dart';
import '../widgets/recovery_panel.dart';

class ProgresAnalisisScreen extends StatelessWidget {
  const ProgresAnalisisScreen({
    super.key,
    this.onReadResult,
    this.onBackToInput,
    this.onStartNewAnalysis,
  });

  final VoidCallback? onReadResult;
  final VoidCallback? onBackToInput;
  final VoidCallback? onStartNewAnalysis;

  RecoveryDescriptor _descriptor(AnalysisFailure failure) {
    final recovery = failure.recoveryClass;
    return RecoveryDescriptor(
      title: switch (recovery) {
        RecoveryClass.retrySameInput => 'Temporary analysis failure',
        RecoveryClass.fixInput => 'Source needs attention',
        RecoveryClass.reuploadSource => 'Source needs replacement',
        RecoveryClass.reloadContext => 'Analysis context is unavailable',
        _ => 'Analysis could not complete safely',
      },
      message: failure.userMessage,
      recoveryClass: recovery,
      technicalCode: failure.code,
      stage: failure.stage,
      primaryAction: switch (recovery) {
        RecoveryClass.retrySameInput => RecoveryAction.retryRequest,
        RecoveryClass.fixInput => RecoveryAction.editSource,
        RecoveryClass.reuploadSource => RecoveryAction.replaceSource,
        RecoveryClass.reloadContext => RecoveryAction.startNewAnalysis,
        _ => RecoveryAction.back,
      },
      secondaryAction: recovery == RecoveryClass.retrySameInput
          ? RecoveryAction.editSource
          : null,
    );
  }

  Future<void> _discardUnsaved(
    BuildContext context,
    AnalisisViewModel vm,
  ) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: C.card,
            title: const Text('Discard unsaved result?'),
            content: const Text(
              'This result was not saved. Discarding it returns to the previous '
              'durable analysis state and does not delete previously saved data.',
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
    if (!confirmed) return;
    vm.discardUnsavedResult();
    onBackToInput?.call();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AnalisisViewModel>();
    final failure = vm.failure;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppHeader(title: 'Analysis Progress'),
          const HeaderDivider(),
          const SizedBox(height: 16),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(
              vertical: 24,
              horizontal: 20,
            ),
            decoration: BoxDecoration(
              color: C.accent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                SizedBox(
                  width: 70,
                  height: 70,
                  child: failure != null
                      ? const Icon(
                          Icons.error_outline,
                          color: C.bg,
                          size: 64,
                        )
                      : vm.selesai
                          ? const Icon(
                              Icons.check_circle,
                              color: C.bg,
                              size: 64,
                            )
                          : const CircularProgressIndicator(
                              color: C.bg,
                              strokeWidth: 6,
                            ),
                ),
                const SizedBox(height: 16),
                Text(
                  vm.statusText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: C.accentText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeading(title: 'Analysis steps'),
          const SizedBox(height: 12),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                for (final step in vm.steps) _StepRow(step: step),
              ],
            ),
          ),
          if (failure != null) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: vm.canRetryPersistence
                  ? RecoveryPanel(
                      descriptor: RecoveryDescriptor(
                        title: 'Analysis result is not saved yet',
                        message: failure.userMessage,
                        recoveryClass: RecoveryClass.noAutomaticRecovery,
                        technicalCode: failure.code,
                        stage: failure.stage,
                        primaryAction: RecoveryAction.retryLocalSave,
                        secondaryAction: RecoveryAction.discardUnsavedResult,
                      ),
                      primaryLabel: 'Retry local save',
                      onPrimary: () {
                        vm.retryPersistence();
                      },
                      secondaryLabel: vm.canDiscardUnsavedResult
                          ? 'Discard unsaved result'
                          : null,
                      onSecondary: vm.canDiscardUnsavedResult
                          ? () => _discardUnsaved(context, vm)
                          : null,
                    )
                  : RecoveryPanel(
                      descriptor: _descriptor(failure),
                      primaryLabel: vm.canRetryRequest
                          ? 'Retry request'
                          : failure.recoveryClass == RecoveryClass.reuploadSource
                              ? 'Replace source'
                              : failure.recoveryClass == RecoveryClass.fixInput
                                  ? 'Edit source'
                                  : vm.requiresFreshAnalysis
                                      ? 'Start a new analysis'
                                      : 'Back to input',
                      onPrimary: vm.canRetryRequest
                          ? () {
                              vm.retryRequest();
                            }
                          : vm.requiresFreshAnalysis
                              ? onStartNewAnalysis
                              : onBackToInput,
                      secondaryLabel: vm.canRetryRequest ? 'Edit source' : null,
                      onSecondary: vm.canRetryRequest ? onBackToInput : null,
                    ),
            ),
          ],
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: vm.selesai ? onReadResult : null,
                child: Text(
                  vm.selesai ? 'View Results' : 'Not ready for review',
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'No fake percentage or ETA. The client only shows states it actually knows.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: C.navInactive,
                fontSize: 11,
                height: 1.4,
              ),
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
    final (icon, color, badge) = switch (step.state) {
      AnalysisStepState.done => (
          Icons.check_circle,
          C.kosong,
          'Done',
        ),
      AnalysisStepState.process => (
          Icons.sync,
          C.accent,
          'In progress',
        ),
      AnalysisStepState.waiting => (
          Icons.radio_button_unchecked,
          C.navInactive,
          'Waiting',
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: const TextStyle(
                    color: C.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (step.detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    step.detail,
                    style: const TextStyle(
                      color: C.detailMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            badge,
            style: TextStyle(
              color: color,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onTap,
        child: Text(label),
      ),
    );
  }
}