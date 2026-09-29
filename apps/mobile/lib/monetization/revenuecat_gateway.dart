import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;

enum RevenueCatPurchaseFailureKind {
  cancelled,
  pending,
  notAllowed,
  failed,
}

final class RevenueCatPurchaseFailure implements Exception {
  const RevenueCatPurchaseFailure({
    required this.kind,
    required this.message,
  });

  final RevenueCatPurchaseFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

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

  Future<RevenueCatCustomerSnapshot> purchasePackage({
    required String offeringIdentifier,
    required String packageIdentifier,
  });

  Future<RevenueCatCustomerSnapshot> restorePurchases();
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
    return _customerSnapshot(customerInfo);
  }

  @override
  Future<RevenueCatPackageSnapshot?> getPackage({
    required String offeringIdentifier,
    required String packageIdentifier,
  }) async {
    final package = await _resolvePackage(
      offeringIdentifier: offeringIdentifier,
      packageIdentifier: packageIdentifier,
    );
    if (package == null) {
      return null;
    }

    return RevenueCatPackageSnapshot(
      offeringIdentifier: package.presentedOfferingContext.offeringIdentifier,
      packageIdentifier: package.identifier,
      productIdentifier: package.storeProduct.identifier,
      priceString: package.storeProduct.priceString,
    );
  }

  @override
  Future<RevenueCatCustomerSnapshot> purchasePackage({
    required String offeringIdentifier,
    required String packageIdentifier,
  }) async {
    final package = await _resolvePackage(
      offeringIdentifier: offeringIdentifier,
      packageIdentifier: packageIdentifier,
    );
    if (package == null) {
      throw const RevenueCatPurchaseFailure(
        kind: RevenueCatPurchaseFailureKind.failed,
        message: 'The configured RevenueCat package is unavailable.',
      );
    }

    try {
      final result = await rc.Purchases.purchase(
        rc.PurchaseParams.package(package),
      );
      return _customerSnapshot(result.customerInfo);
    } on PlatformException catch (error) {
      throw _purchaseFailure(error);
    }
  }

  @override
  Future<RevenueCatCustomerSnapshot> restorePurchases() async {
    final customerInfo = await rc.Purchases.restorePurchases();
    return _customerSnapshot(customerInfo);
  }

  Future<rc.Package?> _resolvePackage({
    required String offeringIdentifier,
    required String packageIdentifier,
  }) async {
    final offerings = await rc.Purchases.getOfferings();
    final offering = offerings.all[offeringIdentifier];
    if (offering == null) {
      return null;
    }

    for (final candidate in offering.availablePackages) {
      if (candidate.identifier == packageIdentifier) {
        return candidate;
      }
    }
    return null;
  }

  static RevenueCatCustomerSnapshot _customerSnapshot(
    rc.CustomerInfo customerInfo,
  ) {
    return RevenueCatCustomerSnapshot(
      activeEntitlementIds:
          Set<String>.unmodifiable(customerInfo.entitlements.active.keys),
    );
  }

  static RevenueCatPurchaseFailure _purchaseFailure(
    PlatformException error,
  ) {
    rc.PurchasesErrorCode code;
    try {
      code = rc.PurchasesErrorHelper.getErrorCode(error);
    } on Object {
      code = rc.PurchasesErrorCode.unknownError;
    }

    return switch (code) {
      rc.PurchasesErrorCode.purchaseCancelledError =>
        const RevenueCatPurchaseFailure(
          kind: RevenueCatPurchaseFailureKind.cancelled,
          message: 'Purchase cancelled.',
        ),
      rc.PurchasesErrorCode.paymentPendingError =>
        const RevenueCatPurchaseFailure(
          kind: RevenueCatPurchaseFailureKind.pending,
          message: 'Purchase is pending.',
        ),
      rc.PurchasesErrorCode.purchaseNotAllowedError =>
        const RevenueCatPurchaseFailure(
          kind: RevenueCatPurchaseFailureKind.notAllowed,
          message: 'Purchases are not allowed on this device or account.',
        ),
      _ => RevenueCatPurchaseFailure(
          kind: RevenueCatPurchaseFailureKind.failed,
          message: error.message ?? 'RevenueCat purchase failed.',
        ),
    };
  }
}
