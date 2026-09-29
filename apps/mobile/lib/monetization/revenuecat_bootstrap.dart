import '../config/revenuecat_config.dart';
import 'revenuecat_gateway.dart';
import 'revenuecat_service.dart';

final class RevenueCatBootstrapResult {
  const RevenueCatBootstrapResult._({
    required this.service,
    required this.configurationError,
  });

  const RevenueCatBootstrapResult.ready(RevenueCatService service)
      : this._(
          service: service,
          configurationError: null,
        );

  const RevenueCatBootstrapResult.configurationError(String message)
      : this._(
          service: null,
          configurationError: message,
        );

  final RevenueCatService? service;
  final String? configurationError;
}

Future<RevenueCatBootstrapResult> bootstrapRevenueCat({
  RevenueCatConfig Function()? loadConfig,
  RevenueCatGateway? gateway,
}) async {
  final configLoader = loadConfig ?? RevenueCatConfig.fromDartDefines;

  final RevenueCatConfig config;
  try {
    config = configLoader();
  } on FormatException catch (error) {
    return RevenueCatBootstrapResult.configurationError(error.message);
  }

  final service = RevenueCatService(
    config: config,
    gateway: gateway ?? PurchasesRevenueCatGateway(),
  );
  await service.initialize();
  return RevenueCatBootstrapResult.ready(service);
}
