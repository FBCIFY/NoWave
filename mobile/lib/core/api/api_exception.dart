/// Réponse du backend hors 2xx.
///
/// Les écrans lisent [statusCode] (et parfois [body]) pour choisir le message
/// affiché à l'utilisateur.
class ApiException implements Exception {
  final int statusCode;
  final String body;

  const ApiException({required this.statusCode, required this.body});

  @override
  String toString() {
    return 'Erreur HTTP $statusCode';
  }
}
