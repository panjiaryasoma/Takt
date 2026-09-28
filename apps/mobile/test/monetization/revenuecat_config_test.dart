import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:takt_mobile/config/revenuecat_config.dart';
import 'package:takt_mobile/monetization/revenuecat_contract.dart';

void main() {
  group('RevenueCatConfig', () {
    test('accepts Test Store only for debug builds with test_ key', () {
      final config = RevenueCatConfig.validate(
        appEnv: 'test_store',
        apiKey: 'test_demo_public_key',
        buildMode: AppBuildMode.debug,
      );

      expect(config.environment, RevenueCatEnvironment.testStore);
      expect(config.apiKey, 'test_demo_public_key');
    });

    test('rejects Test Store in profile mode', () {
      expect(
        () => RevenueCatConfig.validate(
          appEnv: 'test_store',
          apiKey: 'test_demo_public_key',
          buildMode: AppBuildMode.profile,
        ),
        throwsFormatException,
      );
    });

    test('rejects Test Store in release mode', () {
      expect(
        () => RevenueCatConfig.validate(
          appEnv: 'test_store',
          apiKey: 'test_demo_public_key',
          buildMode: AppBuildMode.release,
        ),
        throwsFormatException,
      );
    });

    test('rejects Android production key in Test Store environment', () {
      expect(
        () => RevenueCatConfig.validate(
          appEnv: 'test_store',
          apiKey: 'goog_demo_public_key',
          buildMode: AppBuildMode.debug,
        ),
        throwsFormatException,
      );
    });

    test('accepts Android production environment with goog_ key', () {
      final config = RevenueCatConfig.validate(
        appEnv: 'production_android',
        apiKey: 'goog_demo_public_key',
        buildMode: AppBuildMode.release,
      );

      expect(config.environment, RevenueCatEnvironment.productionAndroid);
      expect(config.apiKey, 'goog_demo_public_key');
    });

    test('rejects Test Store key in Android production environment', () {
      expect(
        () => RevenueCatConfig.validate(
          appEnv: 'production_android',
          apiKey: 'test_demo_public_key',
          buildMode: AppBuildMode.release,
        ),
        throwsFormatException,
      );
    });

    test('rejects Test Store example placeholder', () {
      expect(
        () => RevenueCatConfig.validate(
          appEnv: 'test_store',
          apiKey: 'test_REPLACE_ME',
          buildMode: AppBuildMode.debug,
        ),
        throwsFormatException,
      );
    });

    test('rejects Android production example placeholder', () {
      expect(
        () => RevenueCatConfig.validate(
          appEnv: 'production_android',
          apiKey: 'goog_REPLACE_ME',
          buildMode: AppBuildMode.release,
        ),
        throwsFormatException,
      );
    });

    test('rejects secret API keys', () {
      expect(
        () => RevenueCatConfig.validate(
          appEnv: 'production_android',
          apiKey: 'sk_demo_secret_key',
          buildMode: AppBuildMode.release,
        ),
        throwsFormatException,
      );
    });

    test('rejects unsupported public-key prefixes', () {
      expect(
        () => RevenueCatConfig.validate(
          appEnv: 'production_android',
          apiKey: 'appl_demo_public_key',
          buildMode: AppBuildMode.release,
        ),
        throwsFormatException,
      );
    });

    test('rejects missing environment', () {
      expect(
        () => RevenueCatConfig.validate(
          appEnv: '   ',
          apiKey: 'test_demo_public_key',
          buildMode: AppBuildMode.debug,
        ),
        throwsFormatException,
      );
    });

    test('rejects unknown environment', () {
      expect(
        () => RevenueCatConfig.validate(
          appEnv: 'staging',
          apiKey: 'test_demo_public_key',
          buildMode: AppBuildMode.debug,
        ),
        throwsFormatException,
      );
    });

    test('rejects missing API key', () {
      expect(
        () => RevenueCatConfig.validate(
          appEnv: 'test_store',
          apiKey: '   ',
          buildMode: AppBuildMode.debug,
        ),
        throwsFormatException,
      );
    });
  });

  group('RevenueCat contract', () {
    test('freezes canonical catalog and premium feature identifiers', () {
      expect(RevenueCatContract.entitlementIdentifier, 'pro');
      expect(RevenueCatContract.offeringIdentifier, 'default');
      expect(RevenueCatContract.lifetimePackageIdentifier, r'$rc_lifetime');
      expect(
        RevenueCatContract.testStoreProductIdentifier,
        'takt_pro_lifetime_v1',
      );
      expect(
        RevenueCatContract.alternativeCandidatesFeatureIdentifier,
        'alternative_candidates',
      );
    });

    test('premium access is active only for ACTIVE entitlement', () {
      expect(
        FeatureAccessPolicy.canAccess(
          PremiumFeature.alternativeCandidates,
          EntitlementAccess.unknown,
        ),
        isFalse,
      );
      expect(
        FeatureAccessPolicy.canAccess(
          PremiumFeature.alternativeCandidates,
          EntitlementAccess.inactive,
        ),
        isFalse,
      );
      expect(
        FeatureAccessPolicy.canAccess(
          PremiumFeature.alternativeCandidates,
          EntitlementAccess.active,
        ),
        isTrue,
      );
    });

    test('initial state is UNKNOWN and IDLE', () {
      const state = EntitlementState.initial();

      expect(state.access, EntitlementAccess.unknown);
      expect(state.sync, EntitlementSync.idle);
    });

    test('loading preserves last trustworthy access', () {
      const initial = EntitlementState.initial();
      final active = initial.resolved(isActive: true);
      final loading = active.loading();

      expect(loading.access, EntitlementAccess.active);
      expect(loading.sync, EntitlementSync.loading);
    });

    test('first load failure stays UNKNOWN and becomes ERROR', () {
      const initial = EntitlementState.initial();
      final failed = initial.failed();

      expect(failed.access, EntitlementAccess.unknown);
      expect(failed.sync, EntitlementSync.error);
    });

    test('refresh failure preserves ACTIVE access', () {
      const initial = EntitlementState.initial();
      final active = initial.resolved(isActive: true);
      final failed = active.failed();

      expect(failed.access, EntitlementAccess.active);
      expect(failed.sync, EntitlementSync.error);
    });

    test('refresh failure preserves INACTIVE access', () {
      const initial = EntitlementState.initial();
      final inactive = initial.resolved(isActive: false);
      final failed = inactive.failed();

      expect(failed.access, EntitlementAccess.inactive);
      expect(failed.sync, EntitlementSync.error);
    });

    test('successful active resolution becomes ACTIVE and READY', () {
      const initial = EntitlementState.initial();
      final resolved = initial.resolved(isActive: true);

      expect(resolved.access, EntitlementAccess.active);
      expect(resolved.sync, EntitlementSync.ready);
    });

    test('successful inactive resolution becomes INACTIVE and READY', () {
      const initial = EntitlementState.initial();
      final resolved = initial.resolved(isActive: false);

      expect(resolved.access, EntitlementAccess.inactive);
      expect(resolved.sync, EntitlementSync.ready);
    });
  });

  group('repo contract', () {
    test('example configs contain placeholders only', () {
      final testConfig =
          File('config/revenuecat.test.example.json').readAsStringSync();
      final productionConfig =
          File('config/revenuecat.production.example.json').readAsStringSync();

      expect(testConfig, contains('"APP_ENV": "test_store"'));
      expect(testConfig, contains('"REVENUECAT_API_KEY": "test_REPLACE_ME"'));
      expect(productionConfig, contains('"APP_ENV": "production_android"'));
      expect(
        productionConfig,
        contains('"REVENUECAT_API_KEY": "goog_REPLACE_ME"'),
      );
      expect(testConfig, isNot(contains('sk_')));
      expect(productionConfig, isNot(contains('sk_')));
    });

    test('local RevenueCat configs are ignored', () {
      final gitignore = File('.gitignore').readAsStringSync();

      expect(gitignore, contains('/config/*.local.json'));
    });

    test('Android canonical identity is consistent', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final strings =
          File('android/app/src/main/res/values/strings.xml').readAsStringSync();
      final mainActivity = File(
        'android/app/src/main/kotlin/com/panjiaryasoma/takt/MainActivity.kt',
      );
      final oldMainActivity = File(
        'android/app/src/main/kotlin/com/example/takt_mobile/MainActivity.kt',
      );

      expect(gradle, contains('namespace = "com.panjiaryasoma.takt"'));
      expect(gradle, contains('applicationId = "com.panjiaryasoma.takt"'));
      expect(manifest, contains('android:label="@string/app_name"'));
      expect(strings, contains('<string name="app_name">Takt</string>'));
      expect(
        mainActivity.readAsStringSync(),
        contains('package com.panjiaryasoma.takt'),
      );
      expect(oldMainActivity.existsSync(), isFalse);
    });
  });
}
