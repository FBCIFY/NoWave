import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:blueway/core/api/api_exception.dart';
import 'package:blueway/core/device/device_position.dart';
import 'package:blueway/core/device/device_position_reporter.dart';
import 'package:blueway/core/device/device_registration.dart';
import 'package:blueway/core/device/device_service.dart';
import 'package:blueway/core/location/location_service.dart';

/// Faux backend : note chaque position reçue et répond avec les erreurs
/// prévues, une par appel.
class _FakeDeviceService implements DeviceService {
  final List<Object> errors = [];
  final List<DevicePosition> positions = [];

  @override
  Future<void> sendPosition(DevicePosition position) async {
    positions.add(position);
    if (errors.isNotEmpty) throw errors.removeAt(0);
  }

  @override
  Future<void> register({String? fcmToken}) => throw UnimplementedError();

  @override
  Future<void> deactivate() => throw UnimplementedError();
}

class _FakeDeviceRegistration implements DeviceRegistration {
  int registerCalls = 0;

  @override
  Future<void> register({String? refreshedToken}) async => registerCalls++;

  @override
  Future<void> start() => throw UnimplementedError();

  @override
  Future<void> stop() => throw UnimplementedError();

  @override
  Future<void> unregister() => throw UnimplementedError();
}

/// Faux GPS : [canWatch] simule l'autorisation, [positions] le flux.
class _FakeLocationService extends LocationService {
  bool canWatch = true;
  final StreamController<Position> positions =
      StreamController<Position>.broadcast();

  @override
  Future<bool> canWatchPosition() async => canWatch;

  @override
  Stream<Position> watchPosition() => positions.stream;
}

Position _position({
  double latitude = 43.2965,
  double accuracy = 8,
  double heading = 90,
  double speed = 0,
  int second = 0,
}) {
  return Position(
    longitude: 5.3698,
    latitude: latitude,
    timestamp: DateTime.utc(2026, 10, 5, 8, 30, second),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: heading,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: 0,
  );
}

ApiException _error(int statusCode) {
  return ApiException(statusCode: statusCode, body: '');
}

void main() {
  late _FakeDeviceService devices;
  late _FakeDeviceRegistration registration;
  late _FakeLocationService location;
  late DevicePositionReporter reporter;

  setUp(() {
    devices = _FakeDeviceService();
    registration = _FakeDeviceRegistration();
    location = _FakeLocationService();
    reporter = DevicePositionReporter(
      devices: devices,
      registration: registration,
      location: location,
    );
    addTearDown(location.positions.close);
    addTearDown(reporter.stop);
  });

  /// Émet [position] puis laisse l'envoi éventuel se terminer.
  Future<void> emit(Position position) async {
    location.positions.add(position);
    await pumpEventQueue();
  }

  test('envoie tout de suite la première mesure après start', () async {
    await reporter.start();
    await emit(_position());

    expect(devices.positions, hasLength(1));
    expect(devices.positions.single.latitude, 43.2965);
    expect(devices.positions.single.accuracyM, 8);
    expect(
      devices.positions.single.measuredAt,
      DateTime.utc(2026, 10, 5, 8, 30),
    );
  });

  test(
    'les mesures suivantes attendent le tick : seule la dernière part',
    () async {
      await reporter.start();
      await emit(_position(second: 0));
      await emit(_position(second: 10));
      await emit(_position(second: 20));
      expect(devices.positions, hasLength(1));

      await reporter.tick();
      await reporter.tick();

      expect(devices.positions.map((p) => p.measuredAt.second), [0, 20]);
    },
  );

  test('ignore une mesure trop imprécise', () async {
    await reporter.start();
    await emit(_position(accuracy: DevicePosition.maxAccuracyM + 1));
    await reporter.tick();

    expect(devices.positions, isEmpty);
  });

  test('n’envoie le cap qu’en mouvement et s’il est valide', () async {
    await reporter.start();
    await emit(_position(heading: 90, speed: 0.5, second: 0));
    await emit(_position(heading: 90, speed: 3, second: 1));
    await reporter.tick();
    await emit(_position(heading: -1, speed: 3, second: 2));
    await reporter.tick();

    expect(devices.positions.map((p) => p.headingDeg), [null, 90, null]);
  });

  test(
    'sans autorisation, n’écoute pas le GPS jusqu’au tick suivant',
    () async {
      location.canWatch = false;
      await reporter.start();
      expect(location.positions.hasListener, isFalse);

      location.canWatch = true;
      await reporter.tick();
      await emit(_position());

      expect(location.positions.hasListener, isTrue);
      expect(devices.positions, hasLength(1));
    },
  );

  test('404 : réenregistre le téléphone puis renvoie la mesure', () async {
    devices.errors.add(_error(404));
    await reporter.start();
    await emit(_position());

    expect(registration.registerCalls, 1);
    expect(devices.positions, hasLength(2));
  });

  test('409 : abandonne la mesure', () async {
    devices.errors.add(_error(409));
    await reporter.start();
    await emit(_position());
    await reporter.tick();

    expect(devices.positions, hasLength(1));
    expect(registration.registerCalls, 0);
  });

  test('erreur réseau : renvoie la mesure au tick suivant', () async {
    devices.errors.add(TimeoutException('pas de réseau'));
    await reporter.start();
    await emit(_position());
    await reporter.tick();

    expect(devices.positions, hasLength(2));
    expect(
      devices.positions.last.measuredAt,
      devices.positions.first.measuredAt,
    );
  });

  test('erreur du flux GPS : se réabonne au tick suivant', () async {
    await reporter.start();
    location.positions.addError(StateError('GPS coupé'));
    await pumpEventQueue();
    expect(location.positions.hasListener, isFalse);

    await reporter.tick();

    expect(location.positions.hasListener, isTrue);
  });

  test('après stop, n’écoute plus et n’envoie plus rien', () async {
    await reporter.start();
    await reporter.stop();
    await emit(_position());
    await reporter.tick();

    expect(location.positions.hasListener, isFalse);
    expect(devices.positions, isEmpty);
  });

  test(
    'après stop, un 404 en cours ne réenregistre pas le téléphone',
    () async {
      final response = Completer<void>();
      final slowDevices = _SlowDeviceService(response.future);
      reporter = DevicePositionReporter(
        devices: slowDevices,
        registration: registration,
        location: location,
      );
      await reporter.start();
      location.positions.add(_position());
      await pumpEventQueue();

      final stopped = reporter.stop();
      response.completeError(_error(404));
      await stopped;

      expect(registration.registerCalls, 0);
      expect(slowDevices.calls, 1);
    },
  );
}

/// Backend qui ne répond qu'à la fin de [response].
class _SlowDeviceService extends _FakeDeviceService {
  final Future<void> response;
  int calls = 0;

  _SlowDeviceService(this.response);

  @override
  Future<void> sendPosition(DevicePosition position) {
    calls++;
    return response;
  }
}
