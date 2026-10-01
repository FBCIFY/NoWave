import 'package:blueway/features/profile/presentation/alerts_onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/notifications/fake_notification_permission_service.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required Future<void> Function() onEnableAlerts,
    required VoidCallback onDone,
    required FakeNotificationPermissionService permissions,
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: AlertsOnboardingScreen(
          onEnableAlerts: onEnableAlerts,
          onDone: onDone,
          notificationPermissions: permissions,
        ),
      ),
    );
  }

  testWidgets('active les alertes puis demande l’autorisation', (tester) async {
    final permissions = FakeNotificationPermissionService();
    var saveCalls = 0;
    var doneCalls = 0;

    await pumpScreen(
      tester,
      onEnableAlerts: () async => saveCalls++,
      onDone: () => doneCalls++,
      permissions: permissions,
    );

    await tester.tap(find.text('Activer les alertes'));
    // Le spinner tourne jusqu'à ce que le parent change d'écran :
    // pumpAndSettle ne s'arrêterait jamais.
    await tester.pump();

    expect(saveCalls, 1);
    expect(permissions.requestCalls, 1);
    expect(doneCalls, 1);
  });

  testWidgets('« Plus tard » continue sans rien enregistrer ni demander', (
    tester,
  ) async {
    final permissions = FakeNotificationPermissionService();
    var saveCalls = 0;
    var doneCalls = 0;

    await pumpScreen(
      tester,
      onEnableAlerts: () async => saveCalls++,
      onDone: () => doneCalls++,
      permissions: permissions,
    );

    await tester.tap(find.text('Plus tard'));
    await tester.pumpAndSettle();

    expect(saveCalls, 0);
    expect(permissions.requestCalls, 0);
    expect(doneCalls, 1);
  });

  testWidgets('reste sur l’écran et prévient si l’enregistrement échoue', (
    tester,
  ) async {
    final permissions = FakeNotificationPermissionService();
    var doneCalls = 0;

    await pumpScreen(
      tester,
      onEnableAlerts: () async => throw Exception('réseau'),
      onDone: () => doneCalls++,
      permissions: permissions,
    );

    await tester.tap(find.text('Activer les alertes'));
    await tester.pumpAndSettle();

    expect(
      find.text('Impossible d’activer les alertes. Réessayez.'),
      findsOneWidget,
    );
    expect(permissions.requestCalls, 0);
    expect(doneCalls, 0);
    expect(find.text('Activer les alertes'), findsOneWidget);
  });
}
