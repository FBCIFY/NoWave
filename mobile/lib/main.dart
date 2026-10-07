import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'app/app.dart';
import 'core/map/map_config.dart';
import 'core/api/api_service.dart';
import 'core/device/device_position_reporter.dart';
import 'core/device/device_registration.dart';
import 'core/device/device_service.dart';
import 'core/device/installation_id_store.dart';
import 'core/location/location_service.dart';
import 'core/notifications/notification_permission.dart';
import 'core/notifications/push_tokens.dart';
import 'features/auth/data/auth_service.dart';
import 'features/auth/presentation/auth_gate.dart';
import 'features/camera/data/position_estimate_service.dart';
import 'features/map/data/report_tiles.dart';
import 'features/profile/data/profile_service.dart';
import 'features/reports/data/manual_report_service.dart';
import 'features/reports/data/report_detail_service.dart';
import 'firebase_options.dart';

/// Point d'entrée : initialise Firebase et Mapbox, crée les services partagés,
/// puis lance l'app sur [AuthGate], qui choisit le premier écran à afficher.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  MapboxOptions.setAccessToken(MapConfig.accessToken);

  // Services créés une seule fois, puis transmis aux écrans qui en ont besoin.
  final authService = AuthService();
  final inactiveUserEvents = ValueNotifier<int>(0);
  final apiService = ApiService(
    client: http.Client(),
    onUserInactive: () {
      inactiveUserEvents.value++;
    },
  );
  final profileService = ProfileService(
    apiService: apiService,
    getIdToken: authService.getIdToken,
  );
  final reportService = ManualReportService(
    apiService: apiService,
    getIdToken: authService.getIdToken,
  );
  final positionEstimateService = PositionEstimateService(
    apiService: apiService,
    getIdToken: authService.getIdToken,
  );
  final reportTiles = ReportTiles(getIdToken: authService.getIdToken);
  final reportDetailService = ReportDetailService(
    apiService: apiService,
    getIdToken: authService.getIdToken,
  );
  final installationIds = InstallationIdStore();
  final deviceService = DeviceService(
    apiService: apiService,
    getIdToken: authService.getIdToken,
    installationIds: installationIds,
  );
  final deviceRegistration = DeviceRegistration(
    devices: deviceService,
    pushTokens: const PushTokens(),
    permissions: const NotificationPermissionService(),
    installationIds: installationIds,
  );
  final devicePositionReporter = DevicePositionReporter(
    devices: deviceService,
    registration: deviceRegistration,
    location: LocationService(),
  );

  runApp(
    MyApp(
      home: AuthGate(
        authService: authService,
        inactiveUserEvents: inactiveUserEvents,
        profileService: profileService,
        reportService: reportService,
        positionEstimateService: positionEstimateService,
        reportTiles: reportTiles,
        reportDetailService: reportDetailService,
        deviceRegistration: deviceRegistration,
        devicePositionReporter: devicePositionReporter,
      ),
    ),
  );
}
