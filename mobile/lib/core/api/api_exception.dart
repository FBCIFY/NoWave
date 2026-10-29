import 'dart:convert';

/// Réponse du backend hors 2xx.
///
/// Les erreurs API NoWave utilisent la forme :
/// {
///   "error": {
///     "code": "lower_snake_case",
///     "message": "...",
///     "details": ...
///   }
/// }
class ApiException implements Exception {
  final int statusCode;
  final String body;

  const ApiException({required this.statusCode, required this.body});

  String? get code => _readErrorField('code') as String?;

  String? get message => _readErrorField('message') as String?;

  Object? get details => _readErrorField('details');

  Object? _readErrorField(String field) {
    try {
      final decoded = jsonDecode(body);

      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final error = decoded['error'];

      if (error is! Map<String, dynamic>) {
        return null;
      }

      return error[field];
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() {
    return 'Erreur HTTP $statusCode';
  }
}
