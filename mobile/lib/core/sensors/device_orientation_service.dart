import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:precise_compass/precise_compass.dart';

/// Flux continu du cap (par rapport au nord géographique), du tangage et du
/// roulis du téléphone. Utilisé par la boussole de la carte et par la caméra.
class DeviceOrientationService {
  /// Un seul flux pour toute l'app : chaque flux du plugin ouvre le même canal
  /// natif, et un second abonné (la caméra ouverte par-dessus la carte) coupait
  /// le premier. Partagé, le capteur s'arrête seulement quand plus personne
  /// n'écoute.
  static final _shared = SharedCompassReadings(
    PreciseCompass.headingStream(
      config: const CompassConfig(
        reference: HeadingReference.trueNorth,
        rate: SensorRate.normal,
      ),
    ),
    restartWithoutTrueNorth: defaultTargetPlatform == TargetPlatform.android,
  );

  Stream<CompassReading> get readings => _shared.readings;
}

/// Relaie un flux de boussole à tous les abonnés, et le rouvre tant qu'il
/// n'a pas de cap vrai.
///
/// Sur Android, `precise_compass` calcule la déclinaison magnétique une seule
/// fois, à l'ouverture du flux, depuis la dernière position connue du
/// téléphone. Ouvert par la carte avant la permission de localisation ou le
/// premier fix GPS, le flux n'avait jamais de cap vrai : la caméra restait
/// sur « Recherche de l'orientation… ». Le rouvrir refait ce calcul.
class SharedCompassReadings {
  SharedCompassReadings(
    this._source, {
    required this.restartWithoutTrueNorth,
    this.restartInterval = const Duration(seconds: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Stream<CompassReading> _source;

  /// Rouvrir le flux quand le cap vrai manque ; inutile sur iOS, qui
  /// fournit lui-même le cap vrai dès qu'il a une position.
  final bool restartWithoutTrueNorth;

  /// Délai minimal entre deux ouvertures : sans permission de localisation,
  /// le cap vrai ne viendra jamais, et chaque réouverture remet le lissage
  /// à zéro.
  final Duration restartInterval;

  final DateTime Function() _now;

  late final _controller = StreamController<CompassReading>.broadcast(
    onListen: _listen,
    onCancel: _cancel,
  );

  StreamSubscription<CompassReading>? _subscription;

  /// Ouverture du flux en cours.
  DateTime? _openedAt;

  Stream<CompassReading> get readings => _controller.stream;

  void _listen() {
    _openedAt = _now();
    _subscription = _source.listen(_onReading, onError: _controller.addError);
  }

  Future<void> _cancel() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  void _onReading(CompassReading reading) {
    _controller.add(reading);

    final openedAt = _openedAt;
    // Sans cap magnétique, les capteurs manquent : rouvrir n'y changerait
    // rien.
    if (!restartWithoutTrueNorth ||
        reading.headingTrue != null ||
        reading.headingMagnetic == null ||
        openedAt == null ||
        _now().difference(openedAt) < restartInterval) {
      return;
    }
    unawaited(_restart());
  }

  Future<void> _restart() async {
    // Noté avant l'attente : les mesures reçues entre-temps ne relancent pas.
    _openedAt = _now();
    await _cancel();
    // Entre-temps, tout le monde a pu se désabonner, ou un nouvel abonné a
    // déjà rouvert le flux.
    if (_controller.hasListener && _subscription == null) _listen();
  }
}
