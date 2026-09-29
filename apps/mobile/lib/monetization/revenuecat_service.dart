import 'package:flutter/foundation.dart';

import '../config/revenuecat_config.dart';
import 'revenuecat_contract.dart';
import 'revenuecat_gateway.dart';

enum OfferingSync {
  idle,
  loading,
  ready,
  empty,
  error,
}

enum PurchaseSync {
  idle,
  purchasing,
  purchased,
  cancelled,
  pending,
  error,
}

enum RestoreSync {
  idle,
  restoring,
  restored,
  error,
}

final class PremiumOfferingSnapshot {
  const PremiumOfferingSnapshot({
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

final class PremiumOfferingState {
  const PremiumOfferingState._({
    required this.sync,
    required this.offering,
  });

  const PremiumOfferingState.initial()
      : sync = OfferingSync.idle,
        offering = null;

  final OfferingSync sync;
  final PremiumOfferingSnapshot? offering;

  PremiumOfferingState loading() => PremiumOfferingState._(
        sync: OfferingSync.loading,
        offering: offering,
      );

  PremiumOfferingState resolved(PremiumOfferingSnapshot? next) =>
      PremiumOfferingState._(
        sync: next == null ? OfferingSync.empty : OfferingSync.ready,
        offering: next,
      );

  PremiumOfferingState failed() => PremiumOfferingState._(
        sync: OfferingSync.error,
        offering: offering,
      );
}

final class RevenueCatService extends ChangeNotifier {
  RevenueCatService({
    required RevenueCatConfig config,
    required RevenueCatGateway gateway,
  })  : _config = config,
        _gateway = gateway;

  final RevenueCatConfig _config;
  final RevenueCatGateway _gateway;

  Future<void>? _initializeFuture;
  bool _configured = false;
  EntitlementState _entitlement = const EntitlementState.initial();
  PremiumOfferingState _offering = const PremiumOfferingState.initial();
  PurchaseSync _purchaseSync = PurchaseSync.idle;
  RestoreSync _restoreSync = RestoreSync.idle;
  Object? _entitlementError;
  Object? _offeringError;
  Object? _purchaseError;
  Object? _restoreError;
  Object? _configurationError;

  EntitlementState get entitlement => _entitlement;
  PremiumOfferingState get offering => _offering;
  PurchaseSync get purchaseSync => _purchaseSync;
  RestoreSync get restoreSync => _restoreSync;
  bool get isConfigured => _configured;
  bool get operationInProgress =>
      _purchaseSync == PurchaseSync.purchasing ||
      _restoreSync == RestoreSync.restoring;
  Object? get entitlementError => _entitlementError;
  Object? get offeringError => _offeringError;
  Object? get purchaseError => _purchaseError;
  Object? get restoreError => _restoreError;
  Object? get configurationError => _configurationError;

  bool canAccess(PremiumFeature feature) =>
      FeatureAccessPolicy.canAccess(feature, _entitlement.access);

  Future<void> initialize() {
    return _initializeFuture ??= _initializeOnce();
  }

  Future<void> _initializeOnce() async {
    _entitlement = _entitlement.loading();
    _offering = _offering.loading();
    _configurationError = null;
    notifyListeners();

    try {
      await _gateway.configure(apiKey: _config.apiKey);
      _configured = true;
    } catch (error) {
      _configured = false;
      _configurationError = error;
      _entitlement = _entitlement.failed();
      _offering = _offering.failed();
      notifyListeners();
      return;
    }

    await Future.wait<void>([
      refreshEntitlement(),
      refreshOffering(),
    ]);
  }

  Future<void> refreshAll() async {
    if (!_configured) {
      return;
    }
    await Future.wait<void>([
      refreshEntitlement(),
      refreshOffering(),
    ]);
  }

  Future<void> refreshEntitlement() async {
    if (!_configured) {
      return;
    }

    _entitlement = _entitlement.loading();
    _entitlementError = null;
    notifyListeners();

    try {
      final customer = await _gateway.getCustomerInfo();
      _applyCustomer(customer);
    } catch (error) {
      _entitlementError = error;
      _entitlement = _entitlement.failed();
    }
    notifyListeners();
  }

  Future<void> refreshOffering() async {
    if (!_configured) {
      return;
    }

    _offering = _offering.loading();
    _offeringError = null;
    notifyListeners();

    try {
      final package = await _gateway.getPackage(
        offeringIdentifier: RevenueCatContract.offeringIdentifier,
        packageIdentifier: RevenueCatContract.lifetimePackageIdentifier,
      );

      if (package == null) {
        _offering = _offering.resolved(null);
        notifyListeners();
        return;
      }

      if (_config.environment == RevenueCatEnvironment.testStore &&
          package.productIdentifier !=
              RevenueCatContract.testStoreProductIdentifier) {
        throw StateError(
          'RevenueCat Test Store package does not match the canonical product.',
        );
      }

      _offering = _offering.resolved(
        PremiumOfferingSnapshot(
          offeringIdentifier: package.offeringIdentifier,
          packageIdentifier: package.packageIdentifier,
          productIdentifier: package.productIdentifier,
          priceString: package.priceString,
        ),
      );
    } catch (error) {
      _offeringError = error;
      _offering = _offering.failed();
    }
    notifyListeners();
  }

  Future<void> purchaseLifetime() async {
    if (!_configured || operationInProgress) {
      return;
    }

    final currentOffering = _offering.offering;
    if (_offering.sync != OfferingSync.ready || currentOffering == null) {
      _purchaseError = StateError(
        'A RevenueCat offering must be ready before purchase.',
      );
      _purchaseSync = PurchaseSync.error;
      notifyListeners();
      return;
    }

    _restoreError = null;
    _restoreSync = RestoreSync.idle;
    _purchaseError = null;
    _purchaseSync = PurchaseSync.purchasing;
    notifyListeners();

    try {
      final customer = await _gateway.purchasePackage(
        offeringIdentifier: currentOffering.offeringIdentifier,
        packageIdentifier: currentOffering.packageIdentifier,
      );
      _applyCustomer(customer);

      if (_entitlement.access != EntitlementAccess.active) {
        _purchaseError = StateError(
          'Purchase completed without activating the canonical entitlement.',
        );
        _purchaseSync = PurchaseSync.error;
      } else {
        _purchaseSync = PurchaseSync.purchased;
      }
    } on RevenueCatPurchaseFailure catch (error) {
      switch (error.kind) {
        case RevenueCatPurchaseFailureKind.cancelled:
          _purchaseSync = PurchaseSync.cancelled;
        case RevenueCatPurchaseFailureKind.pending:
          _purchaseSync = PurchaseSync.pending;
        case RevenueCatPurchaseFailureKind.notAllowed:
        case RevenueCatPurchaseFailureKind.failed:
          _purchaseError = error;
          _purchaseSync = PurchaseSync.error;
      }
    } on Object catch (error) {
      _purchaseError = error;
      _purchaseSync = PurchaseSync.error;
    }
    notifyListeners();
  }

  Future<void> restorePurchases() async {
    if (!_configured || operationInProgress) {
      return;
    }

    _purchaseError = null;
    _purchaseSync = PurchaseSync.idle;
    _restoreError = null;
    _restoreSync = RestoreSync.restoring;
    notifyListeners();

    try {
      final customer = await _gateway.restorePurchases();
      _applyCustomer(customer);
      _restoreSync = RestoreSync.restored;
    } on Object catch (error) {
      _restoreError = error;
      _restoreSync = RestoreSync.error;
    }
    notifyListeners();
  }

  void clearOperationFeedback() {
    if (operationInProgress) {
      return;
    }
    _purchaseSync = PurchaseSync.idle;
    _restoreSync = RestoreSync.idle;
    _purchaseError = null;
    _restoreError = null;
    notifyListeners();
  }

  void _applyCustomer(RevenueCatCustomerSnapshot customer) {
    _entitlementError = null;
    _entitlement = _entitlement.resolved(
      isActive: customer.activeEntitlementIds.contains(
        RevenueCatContract.entitlementIdentifier,
      ),
    );
  }
}
