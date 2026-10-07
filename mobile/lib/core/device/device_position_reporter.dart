import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../api/api_exception.dart';
import '../location/location_service.dart';
import 'device_position.dart';
import 'device_registration.dart';
import 'device_service.dart';

/// Envoie la position GPS du téléphone au backend, au plus une fois par
/// [interval], tant que l'app est ouverte. Le backend s'en sert pour choisir
/// qui reçoit les alertes à proximité.
///
/// Ne demande jamais l'autorisation de localisation : tant qu'elle manque,
/// chaque tick revérifie, sans rien afficher.
class DevicePositionReporter {
  static const Duration interval = Duration(seconds: 60);

  /// En dessous (≈ 2 nœuds), le cap GPS n'a pas de sens : on envoie `null`.
  static const double minSpeedForHeadingMs = 1;

  final DeviceService _devices;
  final DeviceRegistration _registration;
  final LocationService _location;

  bool _running = false;
  Timer? _timer;
  StreamSubscription<Position>? _subscription;
  bool _subscribing = false;

  /// Dernière mesure exploitable pas encore envoyée.
  DevicePosition? _pending;

  /// Vrai jusqu'à la première mesure après [start], envoyée sans attendre.
  bool _sendNextNow = false;
  Future<void>? _sending;

  factory DevicePositionReporter({
    required DeviceService devices,
    required DeviceRegistration registration,
    required LocationService location,
  }) {
    return DevicePositionReporter._(devices, registration, location);
  }

  DevicePositionReporter._(this._devices, this._registration, this._location);

  /// Démarre le suivi. Sans effet s'il tourne déjà.
  Future<void> start() {
    if (_running || _registration.isSigningOut) return Future.value();
    _running = true;
    _sendNextNow = true;
    _timer = Timer.periodic(interval, (_) => unawaited(tick()));
    return tick();
  }

  /// Arrête le suivi et attend la fin d'un envoi en cours : après [stop],
  /// plus rien ne part vers le backend.
  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _pending = null;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    await _sending;
  }

  /// Écoute le GPS si ce n'est pas déjà fait, puis envoie la mesure en
  /// attente. Appelé toutes les [interval].
  @visibleForTesting
  Future<void> tick() async {
    await _listen();
    await _flush();
  }

  Future<void> _listen() async {
    if (!_running ||
        _registration.isSigningOut ||
        _subscription != null ||
        _subscribing) {
      return;
    }
    _subscribing = true;
    try {
      if (!await _location.canWatchPosition() ||
          !_running ||
          _registration.isSigningOut) {
        return;
      }
      _subscription = _location.watchPosition().listen(
        _onPosition,
        // Flux coupé (GPS désactivé, autorisation retirée) : on se réabonne
        // au prochain tick.
        onError: (Object error) {
          debugPrint('Suivi GPS interrompu : $error');
          unawaited(_subscription?.cancel());
          _subscription = null;
        },
        onDone: () => _subscription = null,
      );
    } catch (error) {
      debugPrint('Suivi GPS impossible : $error');
    } finally {
      _subscribing = false;
    }
  }

  void _onPosition(Position position) {
    if (!_running || _registration.isSigningOut) return;
    final measurement = _toDevicePosition(position);
    // Mesure trop imprécise : le backend garde la dernière position valide.
    if (!measurement.isUsable) return;

    _pending = measurement;
    if (_sendNextNow) {
      _sendNextNow = false;
      unawaited(_flush());
    }
  }

  Future<void> _flush() {
    if (_sending != null ||
        _pending == null ||
        !_running ||
        _registration.isSigningOut) {
      return Future.value();
    }
    final measurement = _pending!;
    _pending = null;
    return _sending = _send(measurement).whenComplete(() => _sending = null);
  }

  Future<void> _send(DevicePosition measurement) async {
    try {
      try {
        await _devices.sendPosition(measurement);
      } on ApiException catch (error) {
        // 404 : téléphone pas (ou plus) enregistré. On l'enregistre, puis on
        // réessaie une fois. Pas après [stop] : la déconnexion le désactive.
        if (error.statusCode != 404 ||
            !_running ||
            _registration.isSigningOut) {
          rethrow;
        }
        await _registration.register();
        if (!_running || _registration.isSigningOut) return;
        await _devices.sendPosition(measurement);
      }
    } on ApiException catch (error) {
      // 409 (mesure plus ancienne que celle du backend) ou autre refus :
      // renvoyer la même mesure ne changerait rien.
      debugPrint('Position refusée par le backend : $error');
    } catch (error) {
      // Réseau : on la garde pour le prochain tick, sauf si plus récente.
      debugPrint('Envoi de la position impossible : $error');
      if (_running && !_registration.isSigningOut) _pending ??= measurement;
    }
  }

  static DevicePosition _toDevicePosition(Position position) {
    final heading = position.heading;
    final hasHeading =
        position.speed >= minSpeedForHeadingMs &&
        heading.isFinite &&
        heading >= 0 &&
        heading < 360;

    return DevicePosition(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyM: position.accuracy,
      headingDeg: hasHeading ? heading : null,
      measuredAt: position.timestamp,
    );
  }
}
