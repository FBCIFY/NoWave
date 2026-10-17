import 'dart:async';

import 'package:precise_compass/precise_compass.dart';

import 'android_device_heading.dart';
import 'android_rotation_service.dart';

/// La carte utilise la matrice brute pour le cap Android ; precise_compass
/// fournit seulement la déclinaison et le repli si le capteur natif manque.
/// Les lectures utilisées par la caméra (NW-150) ne sont pas modifiées.
class AndroidMapHeadings {
  AndroidMapHeadings(
    this._compass,
    this._rotations, {
    this.smoothingFactor = 0.12,
  });

  final Stream<CompassReading> _compass;
  final Stream<AndroidRotationSample> _rotations;
  final double smoothingFactor;
  late final _controller = StreamController<double>.broadcast(
    onListen: _listen,
    onCancel: _cancel,
  );
  StreamSubscription<CompassReading>? _compassSubscription;
  StreamSubscription<AndroidRotationSample>? _rotationSubscription;
  double _declination = 0;
  double? _magnetic;
  bool _fallback = false;

  Stream<double> get headings => _controller.stream;

  void _listen() {
    _magnetic = null;
    _declination = 0;
    _fallback = false;
    _compassSubscription = _compass.listen((reading) {
      final magnetic = reading.headingMagnetic;
      final trueNorth = reading.headingTrue;
      _declination =
          magnetic != null &&
              magnetic.isFinite &&
              trueNorth != null &&
              trueNorth.isFinite
          ? trueNorth - magnetic
          : 0;
      if (_fallback) {
        final heading = trueNorth != null && trueNorth.isFinite
            ? trueNorth
            : magnetic;
        if (heading != null && heading.isFinite) _controller.add(heading);
      } else {
        _emit();
      }
    }, onError: _controller.addError);
    _rotationSubscription = _rotations.listen(
      (sample) {
        final measured = androidDeviceHeading(
          sample.matrix,
          displayRotation: sample.displayRotation,
        );
        if (measured == null) return;
        _fallback = false;
        final previous = _magnetic;
        final delta = previous == null
            ? 0.0
            : (measured - previous + 540) % 360 - 180;
        _magnetic = previous == null
            ? measured
            : (previous + smoothingFactor * delta) % 360;
        _emit();
      },
      onError: (Object error) {
        // precise_compass peut encore fonctionner en accéléromètre/magnétomètre
        // sur les appareils sans aucun capteur de rotation fusionné.
        _fallback = true;
      },
    );
  }

  void _emit() {
    final magnetic = _magnetic;
    if (magnetic != null) _controller.add((magnetic + _declination) % 360);
  }

  Future<void> _cancel() async {
    final compass = _compassSubscription;
    final rotation = _rotationSubscription;
    _compassSubscription = null;
    _rotationSubscription = null;
    await Future.wait([
      if (compass != null) compass.cancel(),
      if (rotation != null) rotation.cancel(),
    ]);
  }
}
