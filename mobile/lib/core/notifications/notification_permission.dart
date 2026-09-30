import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:app_settings/app_settings.dart';

enum NotificationPermission { granted, denied, notDetermined }

NotificationPermission notificationPermissionFrom(AuthorizationStatus status) {
  return switch (status) {
    AuthorizationStatus.authorized ||
    AuthorizationStatus.provisional => NotificationPermission.granted,
    AuthorizationStatus.denied ||
    AuthorizationStatus.deniedPermanently => NotificationPermission.denied,
    AuthorizationStatus.notDetermined => NotificationPermission.notDetermined,
  };
}

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
