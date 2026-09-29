class ApiConfig {
  const ApiConfig._();

  static const baseUrl = String.fromEnvironment(
    'TAKT_API_BASE_URL',
    defaultValue: 'https://takt-production-951d.up.railway.app',
  );
}
