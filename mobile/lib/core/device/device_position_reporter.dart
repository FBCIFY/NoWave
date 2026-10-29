import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../api/api_exception.dart';
import '../location/location_service.dart';
import 'device_position.dart';
import 'device_registration.dart';
import 'device_service.dart';

/// Envoie la position GPS du téléphone au backend, au plus une fois par
/// [interval] et seulement après [minDistanceM] de déplacement, tant que
/// l'app est ouverte, et aussi en arrière-plan après [setBackground]. Le
/// backend s'en sert pour choisir qui reçoit les alertes à proximité.
///
/// Ne demande jamais l'autorisation de localisation : tant qu'elle manque,
/// chaque tick revérifie, sans rien afficher.
class DevicePositionReporter {
  static const Duration interval = Duration(seconds: 60);

  /// En dessous (≈ 2 nœuds), le cap GPS n'a pas de sens : on envoie `null`.
  static const double minSpeedForHeadingMs = 1;

  /// En dessous de cette distance avec la dernière position envoyée, une
  /// mesure ne part pas, sauf si elle est au moins deux fois plus précise :
  /// un téléphone immobile n'envoie plus sa position toutes les [interval].
  /// Le flux GPS, lui, n'est pas filtré : carte et caméra reçoivent chaque
  /// mesure.
  static const double minDistanceM = 50;

  final DeviceService _devices;
  final DeviceRegistration _registration;
  final LocationService _location;
  final Duration Function() _elapsed;
  Duration? _lastAttempt;

  bool _running = false;
  Timer? _timer;
  StreamSubscription<Position>? _subscription;
  bool _subscribing = false;

  /// Suivi gardé quand l'app passe en arrière-plan (alertes activées).
  bool _background = false;

  /// App en arrière-plan, suivi gardé : pas de nouvel abonnement au GPS
  /// avant le retour dans l'app, ni iOS ni Android ne le démarrent sans elle.
  bool _hidden = false;

  /// Dernière mesure exploitable pas encore envoyée.
  DevicePosition? _pending;

  /// Dernière mesure acceptée par le backend, oubliée à [stop] : la première
  /// mesure après [start] part toujours.
  DevicePosition? _lastSent;

  /// Vrai jusqu'à la première mesure après [start], envoyée sans attendre.
  bool _sendNextNow = false;
  Future<void>? _sending;

  factory DevicePositionReporter({
    required DeviceService devices,
    required DeviceRegistration registration,
    required LocationService location,
    Duration Function()? elapsed,
  }) {
    final clock = Stopwatch()..start();
    return DevicePositionReporter._(
      devices,
      registration,
      location,
      elapsed ?? (() => clock.elapsed),
    );
  }

  DevicePositionReporter._(
    this._devices,
    this._registration,
    this._location,
    this._elapsed,
  );

  /// Démarre le suivi, ou le reprend au retour dans l'app. S'il tourne déjà,
  /// écoute le GPS sans attendre le tick si l'autorisation vient d'arriver.
  Future<void> start() {
    _hidden = false;
    if (_registration.isSigningOut) return Future.value();
    if (_running) return _listen();
    _running = true;
    _sendNextNow = true;
    _timer = Timer.periodic(interval, (_) => unawaited(tick()));
    return tick();
  }

  /// Arrête le suivi et attend la fin d'un envoi en cours : après [stop],
  /// plus rien ne part vers le backend.
  Future<void> stop() async {
    _running = false;
    _hidden = false;
    _timer?.cancel();
    _timer = null;
    _pending = null;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    await _sending;
    _lastSent = null;
    _lastAttempt = null;
  }

  /// Garde ou non le suivi quand l'app passe en arrière-plan. Un abonnement
  /// au GPS en cours est relancé avec les nouveaux réglages.
  Future<void> setBackground(bool enabled) async {
    if (_background == enabled) return;
    _background = enabled;
    final subscription = _subscription;
    if (subscription == null) return;
    _subscription = null;
    await subscription.cancel();
    await _listen();
  }

  /// L'app passe en arrière-plan : le suivi s'arrête, sauf après
  /// [setBackground] où il continue sur l'abonnement au GPS en cours.
  Future<void> appHidden() {
    if (!_background) return stop();
    _hidden = true;
    return Future.value();
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
        _hidden ||
        _registration.isSigningOut ||
        _subscription != null ||
        _subscribing) {
      return;
    }
    _subscribing = true;
    try {
      if (!await _location.canWatchPosition() ||
          !_running ||
          _hidden ||
          _registration.isSigningOut) {
        return;
      }
      final positions = _location.watchDevicePosition(background: _background);
      _subscription = positions.listen(
        _onPosition,
        // Flux coupé (GPS désactivé, autorisation retirée) : on se réabonne
        // au prochain tick, ou au retour dans l'app.
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
    final lastAttempt = _lastAttempt;
    if (lastAttempt != null && _elapsed() - lastAttempt < interval) {
      return Future.value();
    }
    _pending = null;
    if (!_isWorthSending(measurement)) return Future.value();
    _lastAttempt = _elapsed();
    return _sending = _send(measurement).whenComplete(() => _sending = null);
  }

  /// Vrai si [measurement] est à au moins [minDistanceM] de la dernière
  /// position envoyée, ou au moins deux fois plus précise qu'elle.
  bool _isWorthSending(DevicePosition measurement) {
    final last = _lastSent;
    if (last == null) return true;
    final distance = Geolocator.distanceBetween(
      last.latitude,
      last.longitude,
      measurement.latitude,
      measurement.longitude,
    );
    return distance >= minDistanceM ||
        measurement.accuracyM <= last.accuracyM / 2;
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
      _lastSent = measurement;
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
