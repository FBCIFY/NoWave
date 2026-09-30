/// Adresse du backend, lue dans `.env.json` au lancement
/// (`--dart-define-from-file`).
class ApiConfig {
  static const String baseUrl = String.fromEnvironment('API_BASE_URL');
}
