import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:blueway/core/map/map_config.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class NetworkMap extends Fake implements MapboxMap {
  @override
  final MapboxHttpService httpService = MapboxHttpService(
    binaryMessenger:
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger,
    channelSuffix: 888,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native sources share a bounded HTTP budget without blocking map creation',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('plugins.flutter.io.888');
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await MapConfig.configureNetwork(NetworkMap());
      expect(calls.single.method, 'map#setMaxRequestsPerHost');
      expect(calls.single.arguments, {'max': 2});
      // A native configuration failure must not stop the map from opening.
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'native-unavailable');
      });
      await expectLater(MapConfig.configureNetwork(NetworkMap()), completes);
    },
  );

  test('flèche 3D native orientée par Mapbox, taille en pixels écran', () {
    final settings = MapConfig.locationPuckSettings(arrow: true);
    final puck = settings.locationPuck?.locationPuck3D;

    expect(settings.enabled, true);
    expect(settings.puckBearingEnabled, true);
    expect(settings.puckBearing, PuckBearing.HEADING);
    expect(settings.pulsingEnabled, false);
    expect(settings.locationPuck?.locationPuck2D, isNull);
    expect(puck?.modelUri, 'asset://assets/models/location_puck.glb');
    expect(puck?.modelScaleMode, ModelScaleMode.VIEWPORT);
    expect(puck?.modelRotation, [0, 0, 0]);
    expect(puck?.modelEmissiveStrength, 1);
    expect(puck?.modelScaleExpression, MapConfig.arrowScaleExpression);
  });

  test('la flèche fait 27,44 points de près et 13,72 entièrement dézoomée', () {
    expect(jsonDecode(MapConfig.arrowScaleExpression), [
      'interpolate',
      ['linear'],
      ['zoom'],
      2,
      [
        'literal',
        [13.72, 13.72, 13.72],
      ],
      6,
      [
        'literal',
        [27.44, 27.44, 27.44],
      ],
    ]);
  });

  test(
    'sans flèche : suivi natif actif, sans point bleu ni image ni cercle',
    () {
      final settings = MapConfig.locationPuckSettings(arrow: false);
      final puck = settings.locationPuck?.locationPuck2D;

      expect(settings.enabled, true);
      expect(settings.puckBearingEnabled, false);
      expect(settings.pulsingEnabled, false);
      expect(settings.showAccuracyRing, false);
      expect(settings.locationPuck?.locationPuck3D, isNull);
      // Vide retire l'image native ; null la conserverait sur Android.
      expect(puck?.topImage, isEmpty);
      expect(puck?.bearingImage, isEmpty);
      expect(puck?.shadowImage, isEmpty);
      expect(puck?.opacity, 0);
    },
  );
}
