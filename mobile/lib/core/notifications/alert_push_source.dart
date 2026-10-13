import 'package:firebase_messaging/firebase_messaging.dart';

/// Frontière SDK injectable : un tap depuis l'arrière-plan et un lancement
/// depuis une notification sont des ouvertures, pas des messages foreground.
abstract interface class AlertPushSource {
  Stream<RemoteMessage> get foreground;
  Stream<RemoteMessage> get opened;
  Future<RemoteMessage?> initialMessage();
}

class FirebaseAlertPushSource implements AlertPushSource {
  @override
  Stream<RemoteMessage> get foreground => FirebaseMessaging.onMessage;
  @override
  Stream<RemoteMessage> get opened => FirebaseMessaging.onMessageOpenedApp;
  @override
  Future<RemoteMessage?> initialMessage() =>
      FirebaseMessaging.instance.getInitialMessage();
}
