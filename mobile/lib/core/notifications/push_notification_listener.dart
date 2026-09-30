import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Écoute les notifications après la vérification du compte.
///
/// L'autorisation n'est pas demandée ici : elle l'est depuis l'écran
/// « Alertes à proximité » ou le profil, quand l'utilisateur active les alertes.
class PushNotificationListener extends StatefulWidget {
  final Widget child;

  const PushNotificationListener({super.key, required this.child});

  @override
  State<PushNotificationListener> createState() =>
      _PushNotificationListenerState();
}

class _PushNotificationListenerState extends State<PushNotificationListener> {
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<String>? _tokenSubscription;

  @override
  void initState() {
    super.initState();
    _messageSubscription = FirebaseMessaging.onMessage.listen(_showMessage);
    _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
      _logToken,
    );
    unawaited(_loadTokenIfAllowed());
  }

  Future<void> _loadTokenIfAllowed() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }

      // Sur iOS, Firebase ne peut pas créer de token FCM avant le token APNs.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        String? apnsToken;
        for (var attempt = 0; attempt < 10 && mounted; attempt++) {
          apnsToken = await messaging.getAPNSToken();
          if (apnsToken != null) break;
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (apnsToken == null) {
          debugPrint('Token APNs indisponible : vérifier la signature iOS.');
          return;
        }
      }

      if (!mounted) return;
      _logToken(await messaging.getToken());
    } catch (error) {
      debugPrint('Initialisation des notifications impossible : $error');
    }
  }

  void _logToken(String? token) {
    if (kDebugMode && token != null) {
      debugPrint('Token FCM pour le test : $token');
    }
  }

  void _showMessage(RemoteMessage message) {
    if (kDebugMode) {
      debugPrint('Notification FCM reçue au premier plan.');
    }
    if (!mounted) return;
    final notification = message.notification;
    final title = notification?.title ?? 'Nouvelle notification';
    final body = notification?.body;
    final text = body == null || body.isEmpty ? title : '$title — $body';

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    unawaited(_messageSubscription?.cancel());
    unawaited(_tokenSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
