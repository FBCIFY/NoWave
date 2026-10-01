import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:app_settings/app_settings.dart';

/// Autorisation de notifications donnée par le téléphone.
///
/// À ne pas confondre avec la préférence `notificationsEnabled` du profil,
/// enregistrée par le backend : les deux peuvent être différentes.
enum NotificationPermission { granted, denied, notDetermined }

/// Traduit le statut Firebase en [NotificationPermission].
NotificationPermission notificationPermissionFrom(AuthorizationStatus status) {
  return switch (status) {
    AuthorizationStatus.authorized ||
    AuthorizationStatus.provisional => NotificationPermission.granted,
    AuthorizationStatus.denied ||
    AuthorizationStatus.deniedPermanently => NotificationPermission.denied,
    AuthorizationStatus.notDetermined => NotificationPermission.notDetermined,
  };
}

/// Lit ou demande l'autorisation de notifications, ou ouvre les réglages du
/// téléphone. Les tests le remplacent par un faux service.
class NotificationPermissionService {
  const NotificationPermissionService();

  Future<NotificationPermission> getStatus() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return notificationPermissionFrom(settings.authorizationStatus);
  }

  Future<NotificationPermission> request() async {
    final settings = await FirebaseMessaging.instance.requestPermission();
    return notificationPermissionFrom(settings.authorizationStatus);
  }

  Future<void> openSettings() =>
      AppSettings.openAppSettings(type: AppSettingsType.notification);
}
