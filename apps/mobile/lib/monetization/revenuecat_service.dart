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
  Object? _entitlementError;
  Object? _offeringError;
  Object? _configurationError;

  EntitlementState get entitlement => _entitlement;
  PremiumOfferingState get offering => _offering;
  bool get isConfigured => _configured;
  Object? get entitlementError => _entitlementError;
  Object? get offeringError => _offeringError;
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
      _entitlement = _entitlement.resolved(
        isActive: customer.activeEntitlementIds.contains(
          RevenueCatContract.entitlementIdentifier,
        ),
      );
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
}
