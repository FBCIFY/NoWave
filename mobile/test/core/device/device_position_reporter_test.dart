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
  @override
  Future<void> pauseForAccountDeletion() => throw UnimplementedError();

  @override
  Future<void> finishAccountDeletion() => throw UnimplementedError();

  int registerCalls = 0;
  Future<void>? response;

  @override
  bool isSigningOut = false;

  @override
  void beginSignOut() => isSigningOut = true;

  @override
  void cancelSignOut() => isSigningOut = false;

  @override
  void completeSignOut() => throw UnimplementedError();

  @override
  Future<void> register({String? refreshedToken}) async {
    registerCalls++;
    await response;
  }

  @override
  Future<void> start() => throw UnimplementedError();

  @override
  Future<void> stop() => throw UnimplementedError();

  @override
  Future<void> unregister() => throw UnimplementedError();
}

/// Faux GPS : [canWatch] simule l'autorisation, [positions] le flux et
/// [backgroundRequests] le mode demandé à chaque abonnement.
class _FakeLocationService extends LocationService {
  bool canWatch = true;
  final StreamController<Position> positions =
      StreamController<Position>.broadcast();
  final List<bool> backgroundRequests = [];

  @override
  Future<bool> canWatchPosition() async => canWatch;

  @override
  Stream<Position> watchDevicePosition({required bool background}) {
    backgroundRequests.add(background);
    return positions.stream;
  }
}

const _latitude = 43.2965;

/// Sans [latitude], chaque seconde de [second] déplace la mesure d'environ
/// 110 m vers le nord, au-delà de [DevicePositionReporter.minDistanceM].
Position _position({
  double? latitude,
  double accuracy = 8,
  double heading = 90,
  double speed = 0,
  int second = 0,
}) {
  return Position(
    longitude: 5.3698,
    latitude: latitude ?? _latitude + second * 0.001,
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
  var elapsed = Duration.zero;

  setUp(() {
    elapsed = Duration.zero;
    devices = _FakeDeviceService();
    registration = _FakeDeviceRegistration();
    location = _FakeLocationService();
    reporter = DevicePositionReporter(
      devices: devices,
      registration: registration,
      location: location,
      elapsed: () => elapsed,
    );
    addTearDown(location.positions.close);
    addTearDown(reporter.stop);
  });

  /// Émet [position] puis laisse l'envoi éventuel se terminer.
  Future<void> emit(Position position) async {
    location.positions.add(position);
    await pumpEventQueue();
  }

  Future<void> tick() async {
    elapsed += DevicePositionReporter.interval;
    await reporter.tick();
  }

  test(
    'première mesure tardive : attend 60 secondes avant le prochain envoi',
    () async {
      await reporter.start();
      elapsed = const Duration(seconds: 59);
      await emit(_position(second: 0));
      await emit(_position(second: 10));
      elapsed = const Duration(seconds: 60);
      await reporter.tick();
      expect(devices.positions, hasLength(1));
      elapsed = const Duration(seconds: 118);
      await reporter.tick();
      expect(devices.positions, hasLength(1));
      elapsed = const Duration(seconds: 119);
      await reporter.tick();
      expect(devices.positions.map((p) => p.measuredAt.second), [0, 10]);
    },
  );

  test('un échec réseau ne permet pas un réessai avant 60 secondes', () async {
    devices.errors.add(TimeoutException('hors ligne'));
    await reporter.start();
    await emit(_position());
    await reporter.tick();
    expect(devices.positions, hasLength(1));
    await tick();
    expect(devices.positions, hasLength(2));
  });

  test('envoie tout de suite la première mesure après start', () async {
    await reporter.start();
    await emit(_position());

    expect(devices.positions, hasLength(1));
    expect(devices.positions.single.latitude, _latitude);
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

      await tick();
      await tick();

      expect(devices.positions.map((p) => p.measuredAt.second), [0, 20]);
    },
  );

  group('moins de 50 m', () {
    test('immobile : la mesure ne part pas', () async {
      await reporter.start();
      await emit(_position(latitude: _latitude, second: 0));
      // Environ 45 m plus au nord.
      await emit(_position(latitude: _latitude + 0.0004, second: 10));
      await tick();

      expect(devices.positions.map((p) => p.measuredAt.second), [0]);
    });

    test('à 50 m ou plus, la mesure part au tick', () async {
      await reporter.start();
      await emit(_position(latitude: _latitude, second: 0));
      // Environ 56 m plus au nord.
      await emit(_position(latitude: _latitude + 0.0005, second: 10));
      await tick();

      expect(devices.positions.map((p) => p.measuredAt.second), [0, 10]);
    });

    test('deux fois plus précise, la mesure part même immobile', () async {
      await reporter.start();
      await emit(_position(latitude: _latitude, accuracy: 40, second: 0));
      await emit(_position(latitude: _latitude, accuracy: 20, second: 10));
      await tick();
      await emit(_position(latitude: _latitude, accuracy: 15, second: 20));
      await tick();

      expect(devices.positions.map((p) => p.accuracyM), [40, 20]);
    });

    test('une mesure pas envoyée ne compte pas', () async {
      devices.errors.add(TimeoutException('pas de réseau'));
      await reporter.start();
      await emit(_position(latitude: _latitude, second: 0));
      await emit(_position(latitude: _latitude, second: 10));
      await tick();

      expect(devices.positions.map((p) => p.measuredAt.second), [0, 10]);
    });

    test('changer de mode garde la dernière position envoyée', () async {
      await reporter.start();
      await emit(_position(latitude: _latitude, second: 0));
      await reporter.setBackground(true);
      await emit(_position(latitude: _latitude, second: 10));
      await tick();

      expect(devices.positions, hasLength(1));
    });

    test('après stop puis start, la première mesure repart', () async {
      await reporter.start();
      await emit(_position(latitude: _latitude, second: 0));
      await reporter.stop();
      await reporter.start();
      await emit(_position(latitude: _latitude, second: 10));

      expect(devices.positions.map((p) => p.measuredAt.second), [0, 10]);
    });
  });

  test('ignore une mesure trop imprécise', () async {
    await reporter.start();
    await emit(_position(accuracy: DevicePosition.maxAccuracyM + 1));
    await tick();

    expect(devices.positions, isEmpty);
  });

  test('n’envoie le cap qu’en mouvement et s’il est valide', () async {
    await reporter.start();
    await emit(_position(heading: 90, speed: 0.5, second: 0));
    await emit(_position(heading: 90, speed: 3, second: 1));
    await tick();
    await emit(_position(heading: -1, speed: 3, second: 2));
    await tick();

    expect(devices.positions.map((p) => p.headingDeg), [null, 90, null]);
  });

  test(
    'sans autorisation, n’écoute pas le GPS jusqu’au tick suivant',
    () async {
      location.canWatch = false;
      await reporter.start();
      expect(location.positions.hasListener, isFalse);

      location.canWatch = true;
      await tick();
      await emit(_position());

      expect(location.positions.hasListener, isTrue);
      expect(devices.positions, hasLength(1));
    },
  );

  test('start pendant le suivi écoute le GPS sans attendre le tick', () async {
    location.canWatch = false;
    await reporter.start();
    location.canWatch = true;
    await reporter.start();
    await emit(_position());

    expect(location.positions.hasListener, isTrue);
    expect(devices.positions, hasLength(1));
  });

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
    await tick();

    expect(devices.positions, hasLength(1));
    expect(registration.registerCalls, 0);
  });

  test('erreur réseau : renvoie la mesure au tick suivant', () async {
    devices.errors.add(TimeoutException('pas de réseau'));
    await reporter.start();
    await emit(_position());
    await tick();

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

    await tick();

    expect(location.positions.hasListener, isTrue);
  });

  test('après stop, n’écoute plus et n’envoie plus rien', () async {
    await reporter.start();
    await reporter.stop();
    await emit(_position());
    await tick();

    expect(location.positions.hasListener, isFalse);
    expect(devices.positions, isEmpty);
  });

  test('app masquée sans arrière-plan : le suivi s’arrête', () async {
    await reporter.start();
    await reporter.appHidden();
    await emit(_position());
    await tick();

    expect(location.backgroundRequests, [false]);
    expect(location.positions.hasListener, isFalse);
    expect(devices.positions, isEmpty);
  });

  test('app masquée avec arrière-plan : le suivi continue', () async {
    await reporter.setBackground(true);
    await reporter.start();
    await emit(_position(second: 0));
    await reporter.appHidden();
    await emit(_position(second: 10));
    await tick();

    expect(location.backgroundRequests, [true]);
    expect(location.positions.hasListener, isTrue);
    expect(devices.positions.map((p) => p.measuredAt.second), [0, 10]);
  });

  test('app masquée : se réabonne au GPS au retour dans l’app', () async {
    await reporter.setBackground(true);
    await reporter.start();
    await reporter.appHidden();
    location.positions.addError(StateError('GPS coupé'));
    await pumpEventQueue();

    await tick();
    expect(location.positions.hasListener, isFalse);

    await reporter.start();
    await tick();
    expect(location.positions.hasListener, isTrue);
    expect(location.backgroundRequests, [true, true]);
  });

  test('changer de mode relance l’abonnement au GPS en cours', () async {
    await reporter.start();
    await reporter.setBackground(true);
    await reporter.setBackground(false);
    await emit(_position());

    expect(location.backgroundRequests, [false, true, false]);
    expect(location.positions.hasListener, isTrue);
    expect(devices.positions, hasLength(1));
  });

  test('changer de mode à l’arrêt n’abonne pas au GPS', () async {
    await reporter.setBackground(true);

    expect(location.backgroundRequests, isEmpty);
    expect(location.positions.hasListener, isFalse);
  });

  test('une reprise pendant la déconnexion ne relance pas le GPS', () async {
    await reporter.start();
    registration.beginSignOut();
    await reporter.stop();

    await reporter.start();
    await tick();
    await emit(_position());

    expect(location.positions.hasListener, isFalse);
    expect(devices.positions, isEmpty);
  });

  test('une mesure en attente est abandonnée pendant la déconnexion', () async {
    await reporter.start();
    await emit(_position());
    await emit(_position(second: 10));
    registration.beginSignOut();
    await emit(_position(second: 20));
    await tick();

    expect(devices.positions, hasLength(1));
  });

  test('un 404 ne renvoie pas le GPS si la déconnexion commence pendant '
      'le réenregistrement', () async {
    final response = Completer<void>();
    registration.response = response.future;
    devices.errors.add(_error(404));
    await reporter.start();
    await emit(_position());
    expect(registration.registerCalls, 1);

    registration.beginSignOut();
    final stopped = reporter.stop();
    response.complete();
    await stopped;

    expect(devices.positions, hasLength(1));
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
        elapsed: () => elapsed,
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
