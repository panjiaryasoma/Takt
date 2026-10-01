import 'package:flutter/material.dart';

import '../models/recovery_policy.dart';
import '../theme/app_theme.dart';

class RecoveryPanel extends StatelessWidget {
  const RecoveryPanel({
    super.key,
    required this.descriptor,
    this.onPrimary,
    this.onSecondary,
    this.primaryLabel,
    this.secondaryLabel,
  });

  final RecoveryDescriptor descriptor;
  final VoidCallback? onPrimary;
  final VoidCallback? onSecondary;
  final String? primaryLabel;
  final String? secondaryLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          '${descriptor.title}. ${descriptor.message}. ${descriptor.technicalCode}.',
      child: Container(
        key: const Key('recovery-panel'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: C.padat),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.error_outline, color: C.padat, size: 28),
            const SizedBox(height: 8),
            Text(
              descriptor.title,
              style: const TextStyle(
                color: C.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              descriptor.message,
              style: const TextStyle(
                color: C.detailMuted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${descriptor.technicalCode} · ${descriptor.stage}',
              style: const TextStyle(
                color: C.navInactive,
                fontSize: 10,
              ),
            ),
            if (onPrimary != null && primaryLabel != null) ...[
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('recovery-primary-action'),
                onPressed: onPrimary,
                child: Text(primaryLabel!),
              ),
            ],
            if (onSecondary != null && secondaryLabel != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('recovery-secondary-action'),
                onPressed: onSecondary,
                child: Text(secondaryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
