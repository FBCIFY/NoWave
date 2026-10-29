import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// GPS de test qui se comporte comme geolocator sur iOS et Android : un seul
/// flux pour toute l'app, créé avec les réglages du premier abonné et gardé
/// jusqu'au départ de son dernier abonné.
class FakeGeolocator extends GeolocatorPlatform {
  /// Réglages de chaque flux réellement démarré.
  final List<LocationSettings?> started = [];
  int stopped = 0;

  StreamController<Position>? _native;
  Stream<Position>? _cached;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => testPosition();

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    final cached = _cached;
    if (cached != null) return cached;

    started.add(locationSettings);
    final native = _native = StreamController<Position>();
    return _cached = native.stream.asBroadcastStream(
      onCancel: (subscription) {
        unawaited(subscription.cancel());
        _cached = null;
        stopped++;
      },
    );
  }

  /// Nouvelle mesure sur le flux en cours.
  void emit(Position position) => _native!.add(position);

  Future<void> finish() async {
    final native = _native;
    _cached = null;
    await native!.close();
  }
}

Position testPosition({double latitude = 43.2965}) {
  return Position(
    longitude: 5.3698,
    latitude: latitude,
    timestamp: DateTime.utc(2026, 10, 14, 12),
    accuracy: 8,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}
