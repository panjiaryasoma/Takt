import 'package:flutter_test/flutter_test.dart';
import 'package:takt_mobile/config/revenuecat_config.dart';
import 'package:takt_mobile/monetization/revenuecat_bootstrap.dart';
import 'package:takt_mobile/monetization/revenuecat_contract.dart';
import 'package:takt_mobile/monetization/revenuecat_gateway.dart';
import 'package:takt_mobile/monetization/revenuecat_service.dart';

void main() {
  RevenueCatConfig testConfig() => RevenueCatConfig.validate(
        appEnv: 'test_store',
        apiKey: 'test_demo_public_key',
        buildMode: AppBuildMode.debug,
      );

  RevenueCatPackageSnapshot canonicalPackage() =>
      const RevenueCatPackageSnapshot(
        offeringIdentifier: 'default',
        packageIdentifier: r'$rc_lifetime',
        productIdentifier: 'takt_pro_lifetime_v1',
        priceString: r'$0.99',
      );

  group('RevenueCatService initialization', () {
    test('configures once and loads entitlement plus canonical offering',
        () async {
      final gateway = _FakeGateway(
        customer: const RevenueCatCustomerSnapshot(
          activeEntitlementIds: {'pro'},
        ),
        package: canonicalPackage(),
      );
      final service = RevenueCatService(
        config: testConfig(),
        gateway: gateway,
      );

      await Future.wait([service.initialize(), service.initialize()]);

      expect(gateway.configureCalls, 1);
      expect(gateway.customerInfoCalls, 1);
      expect(gateway.packageCalls, 1);
      expect(service.isConfigured, isTrue);
      expect(service.entitlement.access, EntitlementAccess.active);
      expect(service.entitlement.sync, EntitlementSync.ready);
      expect(service.offering.sync, OfferingSync.ready);
      expect(service.offering.offering?.offeringIdentifier, 'default');
      expect(service.offering.offering?.packageIdentifier, r'$rc_lifetime');
      expect(
        service.offering.offering?.productIdentifier,
        'takt_pro_lifetime_v1',
      );
      expect(
        service.canAccess(PremiumFeature.alternativeCandidates),
        isTrue,
      );
    });

    test('configuration failure is fail-closed without inventing access',
        () async {
      final gateway = _FakeGateway(
        configureError: StateError('configure failed'),
      );
      final service = RevenueCatService(
        config: testConfig(),
        gateway: gateway,
      );

      await service.initialize();

      expect(service.isConfigured, isFalse);
      expect(service.configurationError, isNotNull);
      expect(service.entitlement.access, EntitlementAccess.unknown);
      expect(service.entitlement.sync, EntitlementSync.error);
      expect(service.offering.sync, OfferingSync.error);
      expect(
        service.canAccess(PremiumFeature.alternativeCandidates),
        isFalse,
      );
    });
  });

  group('RevenueCat entitlement refresh', () {
    test('inactive customer remains a valid ready state', () async {
      final gateway = _FakeGateway(
        customer: const RevenueCatCustomerSnapshot(
          activeEntitlementIds: {},
        ),
        package: canonicalPackage(),
      );
      final service = RevenueCatService(
        config: testConfig(),
        gateway: gateway,
      );

      await service.initialize();

      expect(service.entitlement.access, EntitlementAccess.inactive);
      expect(service.entitlement.sync, EntitlementSync.ready);
    });

    test('refresh failure preserves last trustworthy active access', () async {
      final gateway = _FakeGateway(
        customer: const RevenueCatCustomerSnapshot(
          activeEntitlementIds: {'pro'},
        ),
        package: canonicalPackage(),
      );
      final service = RevenueCatService(
        config: testConfig(),
        gateway: gateway,
      );
      await service.initialize();

      gateway.customerInfoError = StateError('offline');
      await service.refreshEntitlement();

      expect(service.entitlement.access, EntitlementAccess.active);
      expect(service.entitlement.sync, EntitlementSync.error);
      expect(service.entitlementError, isNotNull);
    });
  });

  group('RevenueCat offering refresh', () {
    test('missing offering or package becomes EMPTY, not fake package',
        () async {
      final gateway = _FakeGateway(
        customer: const RevenueCatCustomerSnapshot(
          activeEntitlementIds: {},
        ),
        package: null,
      );
      final service = RevenueCatService(
        config: testConfig(),
        gateway: gateway,
      );

      await service.initialize();

      expect(service.offering.sync, OfferingSync.empty);
      expect(service.offering.offering, isNull);
    });

    test('refresh failure preserves last trustworthy package', () async {
      final gateway = _FakeGateway(
        customer: const RevenueCatCustomerSnapshot(
          activeEntitlementIds: {},
        ),
        package: canonicalPackage(),
      );
      final service = RevenueCatService(
        config: testConfig(),
        gateway: gateway,
      );
      await service.initialize();

      gateway.packageError = StateError('offline');
      await service.refreshOffering();

      expect(service.offering.sync, OfferingSync.error);
      expect(
        service.offering.offering?.productIdentifier,
        'takt_pro_lifetime_v1',
      );
      expect(service.offeringError, isNotNull);
    });

    test('Test Store rejects package mapped to the wrong product', () async {
      final gateway = _FakeGateway(
        customer: const RevenueCatCustomerSnapshot(
          activeEntitlementIds: {},
        ),
        package: const RevenueCatPackageSnapshot(
          offeringIdentifier: 'default',
          packageIdentifier: r'$rc_lifetime',
          productIdentifier: 'wrong_product',
          priceString: r'$0.99',
        ),
      );
      final service = RevenueCatService(
        config: testConfig(),
        gateway: gateway,
      );

      await service.initialize();

      expect(service.offering.sync, OfferingSync.error);
      expect(service.offering.offering, isNull);
      expect(service.offeringError, isA<StateError>());
    });

    test('canonical selectors are requested from the SDK gateway', () async {
      final gateway = _FakeGateway(
        customer: const RevenueCatCustomerSnapshot(
          activeEntitlementIds: {},
        ),
        package: canonicalPackage(),
      );
      final service = RevenueCatService(
        config: testConfig(),
        gateway: gateway,
      );

      await service.initialize();

      expect(gateway.lastOfferingIdentifier, 'default');
      expect(gateway.lastPackageIdentifier, r'$rc_lifetime');
    });
  });

  group('RevenueCat bootstrap', () {
    test('invalid local config does not crash app startup', () async {
      final gateway = _FakeGateway();

      final result = await bootstrapRevenueCat(
        loadConfig: () => RevenueCatConfig.validate(
          appEnv: '',
          apiKey: '',
          buildMode: AppBuildMode.debug,
        ),
        gateway: gateway,
      );

      expect(result.service, isNull);
      expect(result.configurationError, isNotNull);
      expect(gateway.configureCalls, 0);
    });
  });
}

final class _FakeGateway implements RevenueCatGateway {
  _FakeGateway({
    this.customer = const RevenueCatCustomerSnapshot(
      activeEntitlementIds: {},
    ),
    this.package,
    this.configureError,
  });

  RevenueCatCustomerSnapshot customer;
  RevenueCatPackageSnapshot? package;
  Object? configureError;
  Object? customerInfoError;
  Object? packageError;

  int configureCalls = 0;
  int customerInfoCalls = 0;
  int packageCalls = 0;
  String? lastOfferingIdentifier;
  String? lastPackageIdentifier;

  @override
  Future<void> configure({required String apiKey}) async {
    configureCalls++;
    final error = configureError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<RevenueCatCustomerSnapshot> getCustomerInfo() async {
    customerInfoCalls++;
    final error = customerInfoError;
    if (error != null) {
      throw error;
    }
    return customer;
  }

  @override
  Future<RevenueCatPackageSnapshot?> getPackage({
    required String offeringIdentifier,
    required String packageIdentifier,
  }) async {
    packageCalls++;
    lastOfferingIdentifier = offeringIdentifier;
    lastPackageIdentifier = packageIdentifier;
    final error = packageError;
    if (error != null) {
      throw error;
    }
    return package;
  }
}
