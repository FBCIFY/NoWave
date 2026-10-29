import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:blueway/core/location/location_service.dart';

import 'support/fake_geolocator.dart';

void main() {
  late FakeGeolocator geolocator;
  final location = LocationService();

  setUp(() {
    geolocator = FakeGeolocator();
    GeolocatorPlatform.instance = geolocator;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  /// Le flux de [LocationService] est commun à toute l'app : chaque test
  /// rend ses abonnements, même en échec.
  void listen(Stream<Position> stream, [List<Position>? received]) {
    final subscription = stream.listen(received?.add);
    addTearDown(subscription.cancel);
  }

  test('carte et suivi partagent un seul flux GPS', () async {
    final map = <Position>[];
    final tracking = <Position>[];
    listen(location.watchPosition(), map);
    listen(location.watchDevicePosition(background: false), tracking);

    geolocator.emit(testPosition());
    await pumpEventQueue();

    expect(geolocator.started, hasLength(1));
    expect(map, hasLength(1));
    expect(tracking, hasLength(1));
  });

  test(
    'fin native : avertit les abonnés puis reprend le flux partagé',
    () async {
      final received = <Position>[];
      final errors = <Object>[];
      final map = location.watchPosition().listen(
        received.add,
        onError: errors.add,
      );
      final tracking = location
          .watchDevicePosition(background: true)
          .listen((_) {}, onError: (Object _) {});
      unawaited(geolocator.finish());
      await pumpEventQueue();
      expect(errors, hasLength(1));
      await Future<void>.delayed(const Duration(seconds: 16));
      expect(geolocator.started, hasLength(3));
      expect(
        (geolocator.started.last as AppleSettings)
            .allowBackgroundLocationUpdates,
        isTrue,
      );
      geolocator.emit(testPosition());
      await pumpEventQueue();
      expect(received, hasLength(1));
      await map.cancel();
      await tracking.cancel();
    },
  );

  test('dernier abonné parti : annule la reprise après fin native', () async {
    final subscription = location.watchPosition().listen(
      (_) {},
      onError: (Object _) {},
    );
    unawaited(geolocator.finish());
    await pumpEventQueue();
    await subscription.cancel();
    await Future<void>.delayed(const Duration(seconds: 16));
    expect(geolocator.started, hasLength(1));
  });

  test(
    'le suivi en arrière-plan relance le flux de la carte avec ses réglages',
    () async {
      final map = <Position>[];
      listen(location.watchPosition(), map);

      expect(geolocator.started.single, isNot(isA<AppleSettings>()));

      listen(location.watchDevicePosition(background: true));

      expect(geolocator.stopped, 1);
      expect(geolocator.started, hasLength(2));
      final settings = geolocator.started.last as AppleSettings;
      expect(settings.allowBackgroundLocationUpdates, isTrue);
      expect(settings.pauseLocationUpdatesAutomatically, isFalse);

      geolocator.emit(testPosition());
      await pumpEventQueue();

      expect(map, hasLength(1));
    },
  );

  test(
    'sans abonné, le flux s’arrête et repart ensuite sans arrière-plan',
    () async {
      final tracking = location
          .watchDevicePosition(background: true)
          .listen((_) {});
      await tracking.cancel();

      expect(geolocator.stopped, 1);

      listen(location.watchPosition());

      expect(geolocator.started, hasLength(2));
      expect(geolocator.started.last, isNot(isA<AppleSettings>()));
    },
  );
}
