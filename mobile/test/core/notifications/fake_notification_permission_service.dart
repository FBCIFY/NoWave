import 'package:blueway/core/notifications/notification_permission.dart';

/// Remplace l'autorisation du téléphone dans les tests.
///
/// `request()` simule un utilisateur qui répond « Autoriser ».
class FakeNotificationPermissionService
    implements NotificationPermissionService {
  NotificationPermission status;

  FakeNotificationPermissionService([
    this.status = NotificationPermission.notDetermined,
  ]);

  @override
  Future<NotificationPermission> getStatus() async => status;

  int requestCalls = 0;

  @override
  Future<NotificationPermission> request() async {
    requestCalls++;
    status = NotificationPermission.granted;
    return status;
  }

  int openSettingsCalls = 0;

  @override
  Future<void> openSettings() async {
    openSettingsCalls++;
  }
}
