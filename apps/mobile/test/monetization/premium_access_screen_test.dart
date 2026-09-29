import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:takt_mobile/config/revenuecat_config.dart';
import 'package:takt_mobile/monetization/revenuecat_gateway.dart';
import 'package:takt_mobile/monetization/revenuecat_service.dart';
import 'package:takt_mobile/screens/premium_access_screen.dart';

void main() {
  testWidgets('premium entry point purchases canonical lifetime package',
      (tester) async {
    final gateway = _PaywallGateway();
    final service = RevenueCatService(
      config: RevenueCatConfig.validate(
        appEnv: 'test_store',
        apiKey: 'test_demo_public_key',
        buildMode: AppBuildMode.debug,
      ),
      gateway: gateway,
    );
    await service.initialize();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: service,
        child: const MaterialApp(home: PremiumAccessScreen()),
      ),
    );

    expect(find.text(r'Get lifetime access · $0.99'), findsOneWidget);

    await tester.tap(find.text(r'Get lifetime access · $0.99'));
    await tester.pumpAndSettle();

    expect(gateway.purchaseCalls, 1);
    expect(gateway.lastOfferingIdentifier, 'default');
    expect(gateway.lastPackageIdentifier, r'$rc_lifetime');
    expect(find.text('Takt Pro is active'), findsOneWidget);
    expect(
      find.text('Purchase complete. The Pro entitlement is active.'),
      findsOneWidget,
    );
  });

  testWidgets('purchase cancellation renders non-fatal feedback',
      (tester) async {
    final gateway = _PaywallGateway(
      purchaseError: const RevenueCatPurchaseFailure(
        kind: RevenueCatPurchaseFailureKind.cancelled,
        message: 'cancelled',
      ),
    );
    final service = RevenueCatService(
      config: RevenueCatConfig.validate(
        appEnv: 'test_store',
        apiKey: 'test_demo_public_key',
        buildMode: AppBuildMode.debug,
      ),
      gateway: gateway,
    );
    await service.initialize();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: service,
        child: const MaterialApp(home: PremiumAccessScreen()),
      ),
    );

    await tester.tap(find.text(r'Get lifetime access · $0.99'));
    await tester.pumpAndSettle();

    expect(
      find.text('Purchase cancelled. Nothing was changed.'),
      findsOneWidget,
    );
    expect(find.text('Unlock Takt Pro'), findsOneWidget);
  });
}

final class _PaywallGateway implements RevenueCatGateway {
  _PaywallGateway({this.purchaseError});

  final Object? purchaseError;
  int purchaseCalls = 0;
  String? lastOfferingIdentifier;
  String? lastPackageIdentifier;

  @override
  Future<void> configure({required String apiKey}) async {}

  @override
  Future<RevenueCatCustomerSnapshot> getCustomerInfo() async {
    return const RevenueCatCustomerSnapshot(activeEntitlementIds: {});
  }

  @override
  Future<RevenueCatPackageSnapshot?> getPackage({
    required String offeringIdentifier,
    required String packageIdentifier,
  }) async {
    return const RevenueCatPackageSnapshot(
      offeringIdentifier: 'default',
      packageIdentifier: r'$rc_lifetime',
      productIdentifier: 'takt_pro_lifetime_v1',
      priceString: r'$0.99',
    );
  }

  @override
  Future<RevenueCatCustomerSnapshot> purchasePackage({
    required String offeringIdentifier,
    required String packageIdentifier,
  }) async {
    purchaseCalls++;
    lastOfferingIdentifier = offeringIdentifier;
    lastPackageIdentifier = packageIdentifier;
    final error = purchaseError;
    if (error != null) {
      throw error;
    }
    return const RevenueCatCustomerSnapshot(
      activeEntitlementIds: {'pro'},
    );
  }

  @override
  Future<RevenueCatCustomerSnapshot> restorePurchases() async {
    return const RevenueCatCustomerSnapshot(activeEntitlementIds: {});
  }
}
