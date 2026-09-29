import 'package:purchases_flutter/purchases_flutter.dart' as rc;

final class RevenueCatCustomerSnapshot {
  const RevenueCatCustomerSnapshot({
    required this.activeEntitlementIds,
  });

  final Set<String> activeEntitlementIds;
}

final class RevenueCatPackageSnapshot {
  const RevenueCatPackageSnapshot({
    required this.offeringIdentifier,
    required this.packageIdentifier,
    required this.productIdentifier,
    required this.priceString,
  });

  final String offeringIdentifier;
  final String packageIdentifier;
  final String productIdentifier;
  final String priceString;
}

abstract interface class RevenueCatGateway {
  Future<void> configure({required String apiKey});

  Future<RevenueCatCustomerSnapshot> getCustomerInfo();

  Future<RevenueCatPackageSnapshot?> getPackage({
    required String offeringIdentifier,
    required String packageIdentifier,
  });
}

final class PurchasesRevenueCatGateway implements RevenueCatGateway {
  bool _configuredByThisGateway = false;

  @override
  Future<void> configure({required String apiKey}) async {
    if (_configuredByThisGateway || await rc.Purchases.isConfigured) {
      _configuredByThisGateway = true;
      return;
    }

    final configuration = rc.PurchasesConfiguration(apiKey);
    await rc.Purchases.configure(configuration);
    _configuredByThisGateway = true;
  }

  @override
  Future<RevenueCatCustomerSnapshot> getCustomerInfo() async {
    final customerInfo = await rc.Purchases.getCustomerInfo();
    return RevenueCatCustomerSnapshot(
      activeEntitlementIds:
          Set<String>.unmodifiable(customerInfo.entitlements.active.keys),
    );
  }

  @override
  Future<RevenueCatPackageSnapshot?> getPackage({
    required String offeringIdentifier,
    required String packageIdentifier,
  }) async {
    final offerings = await rc.Purchases.getOfferings();
    final offering = offerings.all[offeringIdentifier];
    if (offering == null) {
      return null;
    }

    final package = offering.getPackage(packageIdentifier);
    if (package == null) {
      return null;
    }

    return RevenueCatPackageSnapshot(
      offeringIdentifier: offering.identifier,
      packageIdentifier: package.identifier,
      productIdentifier: package.storeProduct.identifier,
      priceString: package.storeProduct.priceString,
    );
  }
}
