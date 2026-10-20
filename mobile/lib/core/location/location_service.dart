import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Position GPS du téléphone.
class LocationService {
  /// geolocator ne garde qu'un flux GPS pour toute l'app, avec les réglages
  /// du premier abonné : carte, caméra et suivi passent donc tous par ce flux
  /// commun.
  static final _positions = _SharedPositionStream();

  /// Récupère la position une fois, en demandant l'autorisation si besoin.
  ///
  /// Lève une [StateError] avec un message prêt à afficher si la localisation
  /// est désactivée ou refusée.
  Future<Position> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw StateError(
        'La localisation est désactivée. Activez-la dans les réglages.',
      );
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw StateError('L’accès à votre position a été refusé.');
    }

    if (permission == LocationPermission.deniedForever) {
      throw StateError(
        'L’accès à votre position est bloqué. Autorisez-le dans les réglages.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  /// Vrai si le suivi peut démarrer sans rien demander à l'utilisateur :
  /// localisation activée et déjà autorisée.
  Future<bool> canWatchPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// Suivi continu, une fois l'autorisation obtenue par [getCurrentPosition].
  Stream<Position> watchPosition() => _positions.stream;

  /// Suivi continu pour envoyer la position au backend. Avec [background], il
  /// continue quand l'app passe en arrière-plan : bandeau bleu sur iOS,
  /// notification permanente sur Android.
  ///
  /// À démarrer app visible : ni iOS ni Android ne le lancent en arrière-plan.
  /// C'est le flux de [watchPosition] : changer [background] le relance pour
  /// tous ses abonnés.
  Stream<Position> watchDevicePosition({required bool background}) {
    _positions.background = background;
    return _positions.stream;
  }

  // Sans distanceFilter : chaque mesure, même immobile. Le halo de la carte
  // rétrécit quand la précision s'améliore.
  static LocationSettings _settings({required bool background}) {
    if (!background) {
      return const LocationSettings(accuracy: LocationAccuracy.high);
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.otherNavigation,
        // Sinon iOS coupe le GPS d'un bateau au mouillage et ne le relance
        // pas tant que l'app reste en arrière-plan.
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      ),
      TargetPlatform.android => AndroidSettings(
        accuracy: LocationAccuracy.high,
        // Service de premier plan : Android garde l'app et le GPS actifs,
        // écran éteint compris (wake lock).
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'NoWave suit votre position',
          notificationText:
              'Pour vous alerter des dangers signalés autour de vous.',
          notificationChannelName: 'Suivi de position',
          enableWakeLock: true,
          setOngoing: true,
        ),
      ),
      _ => const LocationSettings(accuracy: LocationAccuracy.high),
    };
  }
}

/// Un seul abonnement à geolocator tant que le flux a des abonnés, relancé
/// avec les nouveaux réglages quand [background] change. Sans ça, le premier
/// abonné (souvent la carte) imposerait ses réglages au suivi.
class _SharedPositionStream {
  StreamSubscription<Position>? _source;
  Timer? _retry;
  int _generation = 0;
  bool _background = false;

  late final _controller = StreamController<Position>.broadcast(
    onListen: _listen,
    onCancel: () {
      _cancel();
      // Plus d'abonné : le prochain repart sans arrière-plan, tant que le
      // suivi ne le redemande pas.
      _background = false;
    },
  );

  Stream<Position> get stream => _controller.stream;

  set background(bool enabled) {
    if (enabled == _background) return;
    _background = enabled;
    if (_source == null) return;
    _cancel();
    _listen();
  }

  void _listen() {
    _retry?.cancel();
    _retry = null;
    if (!_controller.hasListener || _source != null) return;
    final generation = ++_generation;
    try {
      _source =
          Geolocator.getPositionStream(
            locationSettings: LocationService._settings(
              background: _background,
            ),
          ).listen(
            (position) {
              if (generation == _generation) _controller.add(position);
            },
            onError: (Object error, StackTrace stack) {
              if (generation == _generation) _controller.addError(error, stack);
            },
            onDone: () {
              if (generation != _generation) return;
              _source = null;
              _controller.addError(StateError('Le flux GPS s’est interrompu.'));
              _scheduleRetry();
            },
          );
    } catch (error, stack) {
      _controller.addError(error, stack);
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (!_controller.hasListener) return;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 15), _listen);
  }

  void _cancel() {
    _generation++;
    _retry?.cancel();
    _retry = null;
    unawaited(_source?.cancel());
    _source = null;
  }
}
