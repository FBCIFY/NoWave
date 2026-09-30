import 'package:blueway/core/notifications/notification_permission.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('traduit les statuts Firebase en permission NoWave', () {
    expect(
      notificationPermissionFrom(AuthorizationStatus.authorized),
      NotificationPermission.granted,
    );
    expect(
      notificationPermissionFrom(AuthorizationStatus.provisional),
      NotificationPermission.granted,
    );
    expect(
      notificationPermissionFrom(AuthorizationStatus.denied),
      NotificationPermission.denied,
    );
    expect(
      notificationPermissionFrom(AuthorizationStatus.deniedPermanently),
      NotificationPermission.denied,
    );
    expect(
      notificationPermissionFrom(AuthorizationStatus.notDetermined),
      NotificationPermission.notDetermined,
    );
  });
}
