import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Token FCM de ce téléphone, lu auprès de Firebase. Les tests le remplacent
/// par un faux service.
class PushTokens {
  const PushTokens();

  Stream<String> get onTokenRefresh =>
      FirebaseMessaging.instance.onTokenRefresh;

  /// Token actuel, ou `null` si Firebase ne peut pas en créer (iOS sans token
  /// APNs : simulateur ou signature incorrecte).
  Future<String?> getToken() async {
    final messaging = FirebaseMessaging.instance;

    // Sur iOS, Firebase ne peut pas créer de token FCM avant le token APNs.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      String? apnsToken;
      for (var attempt = 0; attempt < 10; attempt++) {
        apnsToken = await messaging.getAPNSToken();
        if (apnsToken != null) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (apnsToken == null) {
        debugPrint('Token APNs indisponible : vérifier la signature iOS.');
        return null;
      }
    }

    final token = await messaging.getToken();
    // Jamais la valeur du token dans les journaux, même en debug (NW-144).
    debugPrint(
      token == null ? 'Token FCM indisponible.' : 'Token FCM obtenu.',
    );
    return token;
  }

  /// Invalide le token actuel : le prochain [getToken] en crée un nouveau.
  Future<void> deleteToken() => FirebaseMessaging.instance.deleteToken();
}
