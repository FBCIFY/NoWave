import 'package:blueway/core/map/globe_pitch_controller.dart';
import 'package:blueway/features/map/presentation/map_alert_camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../support/focus_fakes.dart';

void main() {
  const viewport = Size(390, 844);

  test('transmet les deux points et les marges au calcul natif', () async {
    final map = FocusMap();
    final report = focusReport(longitude: -179.9);
    final camera = await MapAlertCamera.fit(
      map,
      report,
      focusPosition(longitude: 179.9),
      const EdgeInsets.only(top: 44, bottom: 34),
      viewport: viewport,
    );
    expect(map.fittedCoordinates.single.map((p) => p.coordinates.lng), [
      -179.9,
      179.9,
    ]);
    expect(map.fitPadding.single!.top, 176);
    expect(map.fitPadding.single!.bottom, 150);
    expect(map.fitPadding.single!.left, 48);
    expect(map.fitPadding.single!.right, 96);
    expect(camera.zoom, map.nativeZoom);
  });

  test(
    'préserve les zooms natifs différents pour les distances courte et longue',
    () async {
      final map = FocusMap();
      final zooms = <double?>[];
      for (final pair in [(5.3701, 17.0), (25.0, 4.0)]) {
        map.nativeZoom = pair.$2;
        zooms.add(
          (await MapAlertCamera.fit(
            map,
            focusReport(longitude: pair.$1),
            focusPosition(),
            EdgeInsets.zero,
            viewport: viewport,
          )).zoom,
        );
      }
      expect(zooms, [17, 4]);
      expect(map.fittedCoordinates, hasLength(2));
      // Le calcul de projection et du zoom lui-même appartient au SDK natif.
    },
  );

  test('petit écran : les marges laissent un viewport utilisable', () {
    final padding = MapAlertCamera.padding(
      const Size(200, 160),
      const EdgeInsets.all(80),
    );
    expect(padding.top + padding.bottom, lessThan(160));
    expect(padding.left + padding.right, lessThan(200));
  });

  mb.CameraState startCamera({double zoom = 12, double pitch = 0}) =>
      mb.CameraState(
        center: mb.Point(coordinates: mb.Position(5, 43)),
        zoom: zoom,
        pitch: pitch,
        bearing: 0,
        padding: mb.MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
      );

  test('fiche ouverte : report au centre de la carte au-dessus', () async {
    final map = FocusMap();
    final camera = await MapAlertCamera.detail(
      map,
      focusReport(),
      from: startCamera(),
      bearing: 30,
      viewport: viewport,
      panelHeight: 300,
    );
    // Centre visé : le milieu des 544 px restés visibles.
    expect(camera.padding!.bottom, 300);
    expect(camera.padding!.top, 0);
    expect(camera.center!.coordinates.lng, focusReport().longitude);
    expect(camera.zoom, 13.5);
    expect(camera.pitch, GlobePitchController.defaultPitch);
    expect(camera.bearing, 30);
    expect(map.fittedCoordinates, isEmpty);
  });

  test(
    'fiche ouverte : un peu plus près, inclinaison unique, avec limites',
    () async {
      final map = FocusMap();
      Future<mb.CameraOptions> from(
        mb.CameraState camera, {
        double minZoom = 0,
      }) => MapAlertCamera.detail(
        map,
        focusReport(),
        from: camera,
        bearing: 0,
        viewport: viewport,
        panelHeight: viewport.height / 2,
        minZoom: minZoom,
      );
      expect((await from(startCamera(zoom: 16.5, pitch: 30))).zoom, 17);
      // Une carte déjà plus proche n'est pas reculée.
      expect((await from(startCamera(zoom: 18, pitch: 70))).zoom, 18);
      // Inclinaison unique, quelle que soit la vue de départ.
      for (final pitch in [0.0, 30.0, 70.0]) {
        expect(
          (await from(startCamera(pitch: pitch))).pitch,
          GlobePitchController.defaultPitch,
        );
      }
      // Mes alertes depuis une vue large : assez près pour voir le badge.
      expect(
        (await from(
          startCamera(zoom: 4),
          minZoom: MapAlertCamera.historyMinZoom,
        )).zoom,
        MapAlertCamera.historyMinZoom,
      );
    },
  );

  test('fiche plus haute que la carte : marge bornée à la carte', () {
    expect(MapAlertCamera.detailPadding(viewport, 2000).bottom, 844);
    expect(MapAlertCamera.detailPadding(viewport, -4).bottom, 0);
  });

  test(
    'GPS absent, invalide ou ancien : repli sur le seul point API',
    () async {
      for (final position in [
        null,
        focusPosition(latitude: double.nan),
        focusPosition(longitude: 181),
        focusPosition(accuracy: -1),
        focusPosition(
          timestamp: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      ]) {
        final map = FocusMap();
        final camera = await MapAlertCamera.fit(
          map,
          focusReport(longitude: 6, latitude: 44),
          position,
          EdgeInsets.zero,
          viewport: viewport,
        );
        expect(map.fittedCoordinates, isEmpty);
        expect(camera.center!.coordinates.lng, 6);
        expect(camera.center!.coordinates.lat, 44);
        expect(camera.zoom, 16);
      }
    },
  );

  test('viewport nul ou calcul natif invalide : échec explicite', () async {
    final map = FocusMap();
    await expectLater(
      MapAlertCamera.fit(
        map,
        focusReport(),
        focusPosition(),
        EdgeInsets.zero,
        viewport: const Size(0, 844),
      ),
      throwsStateError,
    );
    map.onFit = () async => mb.CameraOptions(zoom: double.nan);
    await expectLater(
      MapAlertCamera.fit(
        map,
        focusReport(),
        focusPosition(),
        EdgeInsets.zero,
        viewport: viewport,
      ),
      throwsStateError,
    );
  });
}
