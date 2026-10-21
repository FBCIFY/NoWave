import 'dart:convert';

import 'package:blueway/features/auth/presentation/widgets/auth_photo_layout.dart';
import 'package:blueway/features/camera/data/position_estimate_service.dart';
import 'package:blueway/features/map/data/report_tiles.dart';
import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:blueway/features/profile/presentation/profile_gate.dart';
import 'package:blueway/features/profile/presentation/profile_onboarding_screen.dart';
import 'package:blueway/features/reports/data/manual_report_service.dart';
import 'package:blueway/features/reports/data/report_detail_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/account_deletion_fixture.dart';

class _Reports extends Fake implements ManualReportService {}

class _Estimates extends Fake implements PositionEstimateService {}

class _Tiles extends Fake implements ReportTiles {
  @override
  void stopPulse() {}
}

class _Details extends Fake implements ReportDetailService {}

Map<String, Object?> _profileJson(Map<String, Object?> changes) => {
  'id': 'profile-a',
  'username': 'Marin',
  'role': 'user',
  'status': 'active',
  'show_user_name': false,
  'show_boat_info': false,
  'notifications_enabled': false,
  'created_at': '2026-10-20T00:00:00Z',
  'updated_at': '2026-10-20T00:00:00Z',
  ...changes,
};

void main() {
  testWidgets('création du profil : un seul écran du nom jusqu’à la carte', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final f = AccountFixture();
    addTearDown(f.dispose);
    // Localisation désactivée : la carte descendra sur la France.
    const geolocator = MethodChannel('flutter.baseflow.com/geolocator');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      geolocator,
      (call) async => call.method == 'isLocationServiceEnabled' ? false : null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(geolocator, null));

    var profileExists = false;
    f.respond = (request) async {
      switch (request.method) {
        case 'GET' when !profileExists:
          return http.Response(
            jsonEncode({
              'error': {'code': 'user_not_found', 'message': 'absent'},
            }),
            404,
          );
        case 'POST':
          profileExists = true;
          final body = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response(jsonEncode(_profileJson(body)), 201);
        case 'PATCH':
          final body = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response(jsonEncode(_profileJson(body)), 200);
        default:
          return http.Response(jsonEncode(_profileJson({})), 200);
      }
    };
    f.respondDevice = (request) async => http.Response(
      jsonEncode({'id': 'boat-1', ...jsonDecode(request.body) as Map}),
      201,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileGate(
          authService: f.auth,
          profileService: f.profiles,
          reportService: _Reports(),
          positionEstimateService: _Estimates(),
          reportTiles: _Tiles(),
          reportDetailService: _Details(),
          deviceRegistration: f.registration,
          devicePositionReporter: f.reporter,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ÉTAPE 1 SUR 5'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'marin');
    await tester.tap(find.text('Créer mon profil'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    // En plein glissement : les deux pages sont là, mais la photo est la
    // même, elle ne glisse pas avec elles.
    expect(find.text('Votre profil'), findsOneWidget);
    expect(find.text('Votre bateau'), findsOneWidget);
    expect(find.byType(AuthPhotoLayout), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(ProfileOnboardingScreen), findsOneWidget);
    expect(find.text('ÉTAPE 2 SUR 5'), findsOneWidget);

    await tester.tap(find.text('Voilier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Sur vos signalements'), findsOneWidget);

    await tester.tap(find.text('Afficher mon bateau'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();

    expect(find.text('Alertes à proximité'), findsOneWidget);
    expect(find.text('ÉTAPE 5 SUR 5'), findsOneWidget);
    expect(
      [for (final r in f.requests) '${r.method} ${r.url.path}'],
      [
        'GET /api/v1/users/me',
        'POST /api/v1/users/me',
        'POST /api/v1/users/me/boat',
        'PATCH /api/v1/users/me',
      ],
    );
    expect(jsonDecode(f.requests[1].body), {'username': 'Marin'});
    expect(jsonDecode(f.requests.last.body), {'show_boat_info': true});
    // La carte se charge déjà sous l'onboarding, sans enregistrer le
    // téléphone.
    expect(find.byType(MapScreen), findsOneWidget);

    await tester.tap(find.text('Plus tard'));
    await tester.pump();
    expect(find.byType(ProfileOnboardingScreen), findsOneWidget);
    // Sans carte native dans les tests : son attente maximale, puis le fondu.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.byType(ProfileOnboardingScreen), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(ProfileOnboardingScreen), findsNothing);
    expect(find.byType(MapScreen), findsOneWidget);
    expect(
      find.text(
        'La localisation est désactivée. Activez-la dans les réglages.',
      ),
      findsOneWidget,
    );
    expect(
      f.requests.map((r) => r.url.path),
      contains('/api/v1/devices/current'),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
