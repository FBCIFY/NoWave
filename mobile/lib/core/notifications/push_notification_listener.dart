import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Affiche les notifications reçues pendant que l'app est ouverte, après la
/// vérification du compte.
///
/// L'autorisation n'est pas demandée ici : elle l'est depuis l'écran
/// « Alertes à proximité » ou le profil, quand l'utilisateur active les alertes.
/// Le token FCM est envoyé au backend par `DeviceRegistration`.
class PushNotificationListener extends StatefulWidget {
  final Widget child;

  const PushNotificationListener({super.key, required this.child});

  @override
  State<PushNotificationListener> createState() =>
      _PushNotificationListenerState();
}

class _PushNotificationListenerState extends State<PushNotificationListener> {
  StreamSubscription<RemoteMessage>? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _messageSubscription = FirebaseMessaging.onMessage.listen(_showMessage);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
