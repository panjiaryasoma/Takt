import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../monetization/revenuecat_contract.dart';
import '../monetization/revenuecat_service.dart';
import '../theme/app_theme.dart';

class PremiumAccessScreen extends StatelessWidget {
  const PremiumAccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<RevenueCatService>();
    final active = service.entitlement.access == EntitlementAccess.active;
    final offering = service.offering.offering;
    final busy = service.operationInProgress;

    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        title: const Text('Takt Pro'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  active ? 'Takt Pro is active' : 'Unlock Takt Pro',
                  style: const TextStyle(
                    color: C.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  active
                      ? 'Your RevenueCat entitlement is active on this account.'
                      : 'Pro unlocks premium access features without changing Takt\'s deadline, eligibility, feasibility, or solver truth.',
                  style: const TextStyle(
                    color: C.detailMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                _OfferingStatus(service: service),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: active ||
                          busy ||
                          service.offering.sync != OfferingSync.ready ||
                          offering == null
                      ? null
                      : service.purchaseLifetime,
                  child: Text(
                    service.purchaseSync == PurchaseSync.purchasing
                        ? 'Purchasing...'
                        : offering == null
                            ? 'Purchase unavailable'
                            : 'Get lifetime access · ${offering.priceString}',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: busy ? null : service.restorePurchases,
                  child: Text(
                    service.restoreSync == RestoreSync.restoring
                        ? 'Restoring...'
                        : 'Restore purchases',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _OperationFeedback(service: service),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'RevenueCat only controls access to premium UI capabilities. Domain facts and planning correctness stay identical for free and Pro users.',
              style: TextStyle(
                color: C.detailMuted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferingStatus extends StatelessWidget {
  const _OfferingStatus({required this.service});

  final RevenueCatService service;

  @override
  Widget build(BuildContext context) {
    return switch (service.offering.sync) {
      OfferingSync.idle || OfferingSync.loading => const Text(
          'Loading RevenueCat offering...',
          style: TextStyle(color: C.detailMuted),
        ),
      OfferingSync.ready => Text(
          'Lifetime package: ${service.offering.offering!.priceString}',
          style: const TextStyle(color: C.accent, fontWeight: FontWeight.w600),
        ),
      OfferingSync.empty => const Text(
          'No RevenueCat package is currently available.',
          style: TextStyle(color: C.detailMuted),
        ),
      OfferingSync.error => Row(
          children: [
            const Expanded(
              child: Text(
                'RevenueCat offering could not be loaded.',
                style: TextStyle(color: C.detailMuted),
              ),
            ),
            TextButton(
              onPressed: service.refreshOffering,
              child: const Text('Retry'),
            ),
          ],
        ),
    };
  }
}

class _OperationFeedback extends StatelessWidget {
  const _OperationFeedback({required this.service});

  final RevenueCatService service;

  @override
  Widget build(BuildContext context) {
    final message = switch (service.purchaseSync) {
      PurchaseSync.purchased =>
        'Purchase complete. The Pro entitlement is active.',
      PurchaseSync.cancelled =>
        'Purchase cancelled. Nothing was changed.',
      PurchaseSync.pending =>
        'Purchase is pending. Access will unlock when the store confirms it.',
      PurchaseSync.error =>
        'Purchase failed. Your existing access state was preserved.',
      _ => switch (service.restoreSync) {
          RestoreSync.restored =>
            service.entitlement.access == EntitlementAccess.active
                ? 'Restore complete. The Pro entitlement is active.'
                : 'Restore complete. No active Pro entitlement was found.',
          RestoreSync.error =>
            'Restore failed. Your existing access state was preserved.',
          _ => null,
        },
    };

    if (message == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: C.white, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: service.clearOperationFeedback,
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }
}
