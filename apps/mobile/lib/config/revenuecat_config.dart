import 'package:flutter/foundation.dart';

enum RevenueCatEnvironment {
  testStore,
  productionAndroid,
}

enum AppBuildMode {
  debug,
  profile,
  release,
}

final class RevenueCatConfig {
  const RevenueCatConfig._({
    required this.environment,
    required this.apiKey,
  });

  final RevenueCatEnvironment environment;
  final String apiKey;

  static RevenueCatConfig fromDartDefines({AppBuildMode? buildMode}) {
    return validate(
      appEnv: const String.fromEnvironment('APP_ENV'),
      apiKey: const String.fromEnvironment('REVENUECAT_API_KEY'),
      buildMode: buildMode ?? currentBuildMode(),
    );
  }

  static RevenueCatConfig validate({
    required String appEnv,
    required String apiKey,
    required AppBuildMode buildMode,
  }) {
    final normalizedEnvironment = appEnv.trim();
    final normalizedApiKey = apiKey.trim();

    if (normalizedEnvironment.isEmpty) {
      throw const FormatException('APP_ENV is required.');
    }
    if (normalizedApiKey.isEmpty) {
      throw const FormatException('REVENUECAT_API_KEY is required.');
    }
    if (normalizedApiKey.startsWith('sk_')) {
      throw const FormatException(
        'RevenueCat secret API keys must never be embedded in the client.',
      );
    }

    switch (normalizedEnvironment) {
      case 'test_store':
        if (buildMode != AppBuildMode.debug) {
          throw const FormatException(
            'RevenueCat Test Store is allowed only in debug builds.',
          );
        }
        if (!_hasValueAfterPrefix(normalizedApiKey, 'test_')) {
          throw const FormatException(
            'Test Store requires a RevenueCat test_ public SDK key.',
          );
        }
        return RevenueCatConfig._(
          environment: RevenueCatEnvironment.testStore,
          apiKey: normalizedApiKey,
        );

      case 'production_android':
        if (!_hasValueAfterPrefix(normalizedApiKey, 'goog_')) {
          throw const FormatException(
            'Android production requires a RevenueCat goog_ public SDK key.',
          );
        }
        return RevenueCatConfig._(
          environment: RevenueCatEnvironment.productionAndroid,
          apiKey: normalizedApiKey,
        );

      default:
        throw FormatException(
          'Unsupported APP_ENV "$normalizedEnvironment".',
        );
    }
  }

  static bool _hasValueAfterPrefix(String value, String prefix) {
    return value.startsWith(prefix) && value.length > prefix.length;
  }
}

AppBuildMode currentBuildMode() {
  if (kReleaseMode) {
    return AppBuildMode.release;
  }
  if (kProfileMode) {
    return AppBuildMode.profile;
  }
  return AppBuildMode.debug;
}
