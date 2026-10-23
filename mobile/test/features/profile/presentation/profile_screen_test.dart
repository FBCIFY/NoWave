import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/boat_service_test.dart' show boatJson;

import '../support/account_deletion_fixture.dart';

import 'package:blueway/features/profile/presentation/boat_screen.dart';

import 'package:blueway/features/profile/domain/user_profile.dart';
import 'package:blueway/features/profile/presentation/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blueway/core/notifications/notification_permission.dart';

import '../../../core/notifications/fake_notification_permission_service.dart';

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

  Future<void> enableAlerts(
    WidgetTester tester,
    FakeNotificationPermissionService permissions,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profile: profile,
          onSignOut: () async {},
          onUpdatePreferences:
              ({showUserName, showBoatInfo, notificationsEnabled}) async =>
                  profile.copyWith(notificationsEnabled: notificationsEnabled),
          notificationPermissions: permissions,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('notificationsEnabledSwitch')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'précharge le bateau et partage la requête jusqu’à sa réouverture',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final f = AccountFixture();
      addTearDown(f.dispose);
      final response = Completer<http.Response>();
      f.respondDevice = (_) => response.future;
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            profile: profile,
            profileService: f.profiles,
            onSignOut: () async {},
            onUpdatePreferences: unusedUpdate,
            notificationPermissions: FakeNotificationPermissionService(),
          ),
        ),
      );
      await tester.pump();
      expect(
        f.requests.where((request) => request.url.path.endsWith('/boat')),
        hasLength(1),
      );
      await tester.tap(find.text('Mon bateau'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        f.requests.where((request) => request.url.path.endsWith('/boat')),
        hasLength(1),
      );
      response.complete(http.Response(jsonEncode(boatJson), 200));
      await tester.pumpAndSettle();
      expect(find.text('Aurore'), findsOneWidget);
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mon bateau'));
      await tester.pumpAndSettle();
      expect(find.text('Aurore'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        f.requests.where((request) => request.url.path.endsWith('/boat')),
        hasLength(1),
      );
    },
  );

  testWidgets('profil ouvre le bateau et le parcours de suppression', (
    tester,
  ) async {
    final f = AccountFixture();
    addTearDown(f.dispose);
    var requested = false;
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profile: profile,
          profileService: f.profiles,
          onSignOut: () async {},
          onUpdatePreferences: unusedUpdate,
          onDeleteAccount: () async {
            requested = true;
          },
          notificationPermissions: FakeNotificationPermissionService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mon bateau'));
    await tester.pumpAndSettle();
    expect(find.byType(BoatScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gestion du compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer mon compte'));
    await tester.pumpAndSettle();
    expect(requested, isTrue);
    expect(f.auth.signOutCalls, 0);
    expect(f.requests.where((r) => r.method == 'DELETE'), isEmpty);
  });

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
    expect(find.text('Utilisateur'), findsNothing);
    expect(find.text('Rôle'), findsNothing);
    expect(find.text('Actif'), findsNothing);
    expect(find.text('Statut'), findsNothing);
    expect(find.text('Supprimer mon compte'), findsNothing);

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

  testWidgets('affiche que les notifications sont bloquées sur le téléphone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profile: profile,
          onSignOut: () async {},
          onUpdatePreferences: unusedUpdate,
          notificationPermissions: FakeNotificationPermissionService(
            NotificationPermission.denied,
          ),
        ),
      ),
    );

    expect(find.text('Bloquées dans les réglages du téléphone'), findsNothing);

    await tester.pump();

    expect(
      find.text('Bloquées dans les réglages du téléphone'),
      findsOneWidget,
    );
  });

  testWidgets('relit l’autorisation quand l’app revient au premier plan', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final permissions = FakeNotificationPermissionService(
      NotificationPermission.denied,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profile: profile,
          onSignOut: () async {},
          onUpdatePreferences: unusedUpdate,
          notificationPermissions: permissions,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Bloquées dans les réglages du téléphone'),
      findsOneWidget,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    permissions.status = NotificationPermission.granted;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Autorisées sur ce téléphone'), findsOneWidget);
  });

  testWidgets('demande l’autorisation si elle n’a jamais été demandée', (
    tester,
  ) async {
    final permissions = FakeNotificationPermissionService();

    await enableAlerts(tester, permissions);

    expect(permissions.requestCalls, 1);
    expect(permissions.openSettingsCalls, 0);
    expect(find.text('Autorisées sur ce téléphone'), findsOneWidget);
  });

  testWidgets('ouvre les réglages si les notifications sont bloquées', (
    tester,
  ) async {
    final permissions = FakeNotificationPermissionService(
      NotificationPermission.denied,
    );

    await enableAlerts(tester, permissions);

    expect(permissions.requestCalls, 0);
    expect(permissions.openSettingsCalls, 1);
  });

  testWidgets('ne redemande rien si les notifications sont déjà autorisées', (
    tester,
  ) async {
    final permissions = FakeNotificationPermissionService(
      NotificationPermission.granted,
    );

    await enableAlerts(tester, permissions);

    expect(permissions.requestCalls, 0);
    expect(permissions.openSettingsCalls, 0);
  });
}
