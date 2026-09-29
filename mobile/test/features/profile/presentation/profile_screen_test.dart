import 'dart:async';

import 'package:blueway/features/profile/domain/user_profile.dart';
import 'package:blueway/features/profile/presentation/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blueway/core/notifications/notification_permission.dart';

void main() {
  final profile = UserProfile(
    id: 'user-123',
    username: 'John',
    dateOfBirth: null,
    nationality: null,
    role: 'user',
    status: 'active',
    showUserName: false,
    showBoatInfo: false,
    notificationsEnabled: false,
    createdAt: DateTime.utc(2026, 9, 22),
    updatedAt: DateTime.utc(2026, 9, 22),
  );

  Future<UserProfile> unusedUpdate({
    bool? showUserName,
    bool? showBoatInfo,
    bool? notificationsEnabled,
  }) async {
    return profile;
  }

  Switch switchFor(WidgetTester tester, String key) {
    return tester.widget<Switch>(find.byKey(Key(key)));
  }

  testWidgets('affiche le profil et les préférences par défaut', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));

    addTearDown(() {
      return tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profile: profile,
          onSignOut: () async {},
          onUpdatePreferences: unusedUpdate,
          notificationPermissions: FakeNotificationPermissionService(),
        ),
      ),
    );

    expect(find.text('John'), findsOneWidget);
    expect(find.text('Utilisateur'), findsOneWidget);
    expect(find.text('Actif'), findsOneWidget);

    final switches = tester.widgetList<Switch>(find.byType(Switch));
    expect(switches, hasLength(3));
    expect(switches.every((preference) => !preference.value), isTrue);
  });

  testWidgets('reste lisible et défilable sur un petit écran', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profile: profile,
          onSignOut: () async {},
          onUpdatePreferences: unusedUpdate,
          notificationPermissions: FakeNotificationPermissionService(),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Se déconnecter'),
      250,
      scrollable: find.byType(Scrollable),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Se déconnecter'), findsOneWidget);
  });

  testWidgets('permet de se déconnecter', (tester) async {
    var signedOut = false;

    addTearDown(() {
      return tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profile: profile,
          onSignOut: () async {
            signedOut = true;
          },
          onUpdatePreferences: unusedUpdate,
          notificationPermissions: FakeNotificationPermissionService(),
        ),
      ),
    );

    final signOutButton = find.text('Se déconnecter');

    await tester.scrollUntilVisible(
      signOutButton,
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(signOutButton);
    await tester.pump();

    expect(signedOut, isTrue);
  });

  testWidgets('active les alertes en envoyant uniquement ce champ', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final calls = <Map<String, bool?>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profile: profile,
          onSignOut: () async {},
          onUpdatePreferences:
              ({showUserName, showBoatInfo, notificationsEnabled}) async {
                calls.add({
                  'showUserName': showUserName,
                  'showBoatInfo': showBoatInfo,
                  'notificationsEnabled': notificationsEnabled,
                });
                return profile.copyWith(
                  notificationsEnabled: notificationsEnabled,
                );
              },
          notificationPermissions: FakeNotificationPermissionService(),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('notificationsEnabledSwitch')));
    await tester.pumpAndSettle();

    expect(calls, [
      {
        'showUserName': null,
        'showBoatInfo': null,
        'notificationsEnabled': true,
      },
    ]);
    expect(switchFor(tester, 'notificationsEnabledSwitch').value, isTrue);
    expect(switchFor(tester, 'showUserNameSwitch').onChanged, isNotNull);
  });

  testWidgets('annule le changement et prévient si l’enregistrement échoue', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final response = Completer<UserProfile>();

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profile: profile,
          onSignOut: () async {},
          onUpdatePreferences:
              ({showUserName, showBoatInfo, notificationsEnabled}) {
                return response.future;
              },
          notificationPermissions: FakeNotificationPermissionService(),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('notificationsEnabledSwitch')));
    await tester.pump();

    expect(switchFor(tester, 'notificationsEnabledSwitch').value, isTrue);
    expect(switchFor(tester, 'showUserNameSwitch').onChanged, isNull);

    response.completeError(Exception('Réseau indisponible'));
    await tester.pumpAndSettle();

    expect(switchFor(tester, 'notificationsEnabledSwitch').value, isFalse);
    expect(switchFor(tester, 'showUserNameSwitch').onChanged, isNotNull);
    expect(
      find.text('Impossible d’enregistrer la préférence. Réessayez.'),
      findsOneWidget,
    );
  });
}

class FakeNotificationPermissionService
    implements NotificationPermissionService {
  NotificationPermission status;

  FakeNotificationPermissionService([
    this.status = NotificationPermission.notDetermined,
  ]);

  @override
  Future<NotificationPermission> getStatus() async => status;

  @override
  Future<NotificationPermission> request() async => status;
}
