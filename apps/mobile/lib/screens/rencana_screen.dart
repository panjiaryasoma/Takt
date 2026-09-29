import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/saved_plan_repository.dart';
import '../theme/app_theme.dart';
import '../viewmodels/saved_plans_view_model.dart';
import '../widgets/common.dart';

class RencanaScreen extends StatelessWidget {
  const RencanaScreen({
    super.key,
    this.onOpen,
  });

  final ValueChanged<SavedPlanSummary>? onOpen;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SavedPlansViewModel>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppHeader(title: 'Saved Plans'),
        const HeaderDivider(),
        const SizedBox(height: 20),
        if (vm.loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: vm.refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                if (vm.error != null)
                  _MessageCard(
                    icon: Icons.error_outline,
                    text: vm.error!,
                  ),
                if (!vm.loading && vm.items.isEmpty)
                  const _MessageCard(
                    icon: Icons.inventory_2_outlined,
                    text:
                        'No accepted plans yet. Evaluate a competition and explicitly accept a candidate first.',
                  ),
                for (final item in vm.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PlanCard(
                      item: item,
                      onTap: () => onOpen?.call(item),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.item,
    required this.onTap,
  });

  final SavedPlanSummary item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final revision = item.currentRevision;
    final accepted = revision.acceptedAt;
    final deadline = item.deadline.toLocal();

    return Material(
      color: C.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.fact_check_outlined,
                    color: C.accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.title,
                      style: const TextStyle(
                        color: C.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _StatusBadge(stale: item.stale),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Revision ${revision.revisionNumber} · ${revision.selectedCandidateId}',
                style: const TextStyle(color: C.detailMuted),
              ),
              const SizedBox(height: 4),
              Text(
                'Accepted ${_dateTime(accepted)}',
                style: const TextStyle(color: C.detailMuted),
              ),
              const SizedBox(height: 4),
              Text(
                'Deadline ${_dateTime(deadline)}',
                style: const TextStyle(color: C.detailMuted),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: onTap,
                  child: const Text('Open plan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.stale});
  final bool stale;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: C.bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: stale ? C.padat : C.accent),
        ),
        child: Text(
          stale ? 'STALE' : 'CURRENT',
          style: TextStyle(
            color: stale ? C.padat : C.accent,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: C.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: C.detailMuted),
              ),
            ),
          ],
        ),
      );
}

String _dateTime(DateTime value) {
  final local = value.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
