import 'package:blueway/features/map/presentation/map_alert_camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../support/focus_fakes.dart';

void main() {
  test('transmet les deux points et les marges au calcul natif', () async {
    final map = FocusMap();
    final report = focusReport(longitude: -179.9);
    final camera = await MapAlertCamera.fit(
      map,
      report,
      focusPosition(longitude: 179.9),
      const EdgeInsets.only(top: 44, bottom: 34),
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

  test('fiche ouverte : le report est cadré dans la partie visible', () async {
    final map = FocusMap();
    final camera = await MapAlertCamera.fit(
      map,
      focusReport(),
      null,
      const EdgeInsets.only(top: 44, bottom: 34),
      sheetHeight: 450,
    );
    expect(camera.zoom, 16);
    expect(camera.padding!.bottom, 470);
    expect(camera.padding!.top, 92);
    expect(camera.padding!.left, camera.padding!.right);
    expect(map.fittedCoordinates, isEmpty);
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
        );
        expect(map.fittedCoordinates, isEmpty);
        expect(camera.center!.coordinates.lng, 6);
        expect(camera.center!.coordinates.lat, 44);
        expect(camera.zoom, 16);
      }
    },
  );

  test('viewport nul ou calcul natif invalide : échec explicite', () async {
    final map = FocusMap()..width = 0;
    await expectLater(
      MapAlertCamera.fit(map, focusReport(), focusPosition(), EdgeInsets.zero),
      throwsStateError,
    );
    map.width = 390;
    map.onFit = () async => mb.CameraOptions(zoom: double.nan);
    await expectLater(
      MapAlertCamera.fit(map, focusReport(), focusPosition(), EdgeInsets.zero),
      throwsStateError,
    );
  });
}
