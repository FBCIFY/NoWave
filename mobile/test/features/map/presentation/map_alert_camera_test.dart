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
    expect(camera.zoom, 13);
    expect(camera.pitch, GlobePitchController.defaultPitch);
    expect(camera.bearing, 30);
    expect(map.fittedCoordinates, isEmpty);
  });

  test(
    'la consultation conserve le zoom proche et l’inclinaison choisie',
    () async {
      final map = FocusMap();
      for (final zoom in [2.0, 4.0, 12.0, 13.0, 16.5, 18.0]) {
        final camera = await MapAlertCamera.detail(
          map,
          focusReport(),
          from: startCamera(zoom: zoom),
          bearing: 0,
          viewport: viewport,
          panelHeight: viewport.height / 2,
          pitch: 30,
        );
        expect(camera.zoom, zoom < 13 ? 13 : zoom);
        expect(camera.pitch, 30);
      }
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
