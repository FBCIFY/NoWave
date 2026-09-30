import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:precise_compass/precise_compass.dart';

import '../../../core/location/location_service.dart';
import '../../../core/location/coordinate_formatter.dart';
import '../../../core/sensors/device_orientation_service.dart';
import '../../../core/sensors/camera_orientation.dart';
import '../domain/capture_requirements.dart';

/// Prototype NW-55, pas encore accessible depuis l'app : aperçu caméra,
/// position GPS et orientation du téléphone.
///
/// La photo n'est autorisée qu'avec une précision GPS d'au plus 50 m et une
/// orientation complète (cap, tangage, roulis). Elle n'est ni enregistrée ni
/// envoyée pour l'instant.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final _locationService = LocationService();
  final _orientationService = DeviceOrientationService();

  geo.Position? _position;
  bool _isLocating = false;
  String? _locationError;
  CameraController? _controller;
  String? _cameraError;
  bool _isCapturing = false;
  String? _captureStatus;
  StreamSubscription<CompassReading>? _orientationSubscription;
  CompassReading? _orientation;
  String? _orientationError;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadPosition();
    _listenToOrientation();
  }

  Future<void> _loadPosition() async {
    setState(() {
      _isLocating = true;
      _locationError = null;
    });

    try {
      final position = await _locationService.getCurrentPosition();

      if (!mounted) return;

      setState(() {
        _position = position;
      });
    } on StateError catch (error) {
      if (!mounted) return;

      setState(() {
        _locationError = error.message;
      });
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _locationError = 'Position GPS introuvable pour le moment.';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _locationError = 'Impossible de récupérer la position GPS.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  void _listenToOrientation() {
    _orientationSubscription = _orientationService.readings.listen(
      (reading) {
        if (!mounted) return;

        setState(() {
          _orientation = reading;
          _orientationError = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;

        setState(() {
          _orientationError = 'Capteurs d’orientation indisponibles.';
        });
      },
    );
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        setState(() {
          _cameraError = 'Aucune caméra disponible sur cet appareil.';
        });
        return;
      }

      final backCameras = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );

      if (backCameras.isEmpty) {
        setState(() {
          _cameraError = 'Aucune caméra arrière disponible sur cet appareil.';
        });
        return;
      }

      final backCamera = backCameras.first;

      final controller = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      _controller = controller;
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {});
    } on CameraException catch (error) {
      if (!mounted) return;

      setState(() {
        _cameraError = _cameraErrorMessage(error);
      });
    }
  }

  bool get _canCapture {
    final controller = _controller;
    final position = _position;
    final orientation = _orientation;

    final orientationAvailable =
        orientation != null &&
        orientation.headingTrue != null &&
        orientation.pitch != null &&
        orientation.roll != null;

    return controller != null &&
        controller.value.isInitialized &&
        !_isLocating &&
        _locationError == null &&
        position != null &&
        isCaptureGpsAccuracySufficient(position.accuracy) &&
        orientationAvailable &&
        !_isCapturing;
  }

  String _captureRequirementStatus() {
    final position = _position;
    final orientation = _orientation;

    if (_isLocating) {
      return 'Capture bloquée : recherche GPS en cours.';
    }

    if (_locationError != null) {
      return 'Capture bloquée : ${_locationError!}';
    }

    if (position == null) {
      return 'Capture bloquée : position GPS indisponible.';
    }

    if (!isCaptureGpsAccuracySufficient(position.accuracy)) {
      return 'Capture bloquée : précision GPS supérieure à '
          '${maxCaptureGpsAccuracyMeters.toStringAsFixed(0)} m.';
    }

    if (orientation == null ||
        orientation.headingTrue == null ||
        orientation.pitch == null ||
        orientation.roll == null) {
      return 'Capture bloquée : orientation du téléphone indisponible.';
    }

    return 'Capture autorisée : GPS et orientation disponibles.';
  }

  Future<void> _capturePhoto() async {
    final controller = _controller;
    final position = _position;
    final orientation = _orientation;

    if (controller == null || position == null || orientation == null) {
      return;
    }

    final heading = orientation.headingTrue;
    final pitch = orientation.pitch;
    final roll = orientation.roll;

    if (!_canCapture || heading == null || pitch == null || roll == null) {
      return;
    }

    final inclination = calculateCameraInclinationDegrees(
      pitchDegrees: pitch,
      rollDegrees: roll,
    );

    setState(() {
      _isCapturing = true;
      _captureStatus = null;
    });

    try {
      await controller.takePicture();

      if (!mounted) return;

      setState(() {
        _captureStatus =
            'Photo capturée.\n'
            'GPS : ${formatDms(position.latitude, isLatitude: true)}, '
            '${formatDms(position.longitude, isLatitude: false)} '
            '(±${position.accuracy.toStringAsFixed(1)} m)\n'
            '${_altitudeStatus(position)}\n'
            'Azimut nord vrai : ${heading.toStringAsFixed(1)}°\n'
            'Inclinaison : ${inclination.toStringAsFixed(1)}°';
      });
    } on CameraException {
      if (!mounted) return;

      setState(() {
        _captureStatus = 'Impossible de prendre la photo.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  String _cameraErrorMessage(CameraException error) {
    if (error.code == 'CameraAccessDenied' ||
        error.code == 'CameraAccessDeniedWithoutPrompt' ||
        error.code == 'CameraAccessRestricted') {
      return 'L’accès à la caméra est refusé. '
          'Autorisez-le dans les réglages du téléphone.';
    }

    return 'Impossible d’ouvrir la caméra.';
  }

  String _orientationStatus() {
    if (_orientationError != null) {
      return _orientationError!;
    }

    final orientation = _orientation;

    if (orientation == null) {
      return 'Recherche de l’orientation…';
    }

    final trueHeading = orientation.headingTrue;
    final pitch = orientation.pitch;
    final roll = orientation.roll;

    final headingText = trueHeading == null
        ? 'Azimut nord vrai : indisponible'
        : 'Azimut nord vrai : ${trueHeading.toStringAsFixed(1)}°';

    final inclination = pitch == null || roll == null
        ? null
        : calculateCameraInclinationDegrees(
            pitchDegrees: pitch,
            rollDegrees: roll,
          );

    final inclinationText = inclination == null
        ? 'Inclinaison de visée : indisponible'
        : 'Inclinaison de visée : ${inclination.toStringAsFixed(1)}°';

    final calibrationText = orientation.shouldCalibrate
        ? '\nCalibration de la boussole recommandée.'
        : '';

    return '$headingText\n$inclinationText$calibrationText';
  }

  String _altitudeStatus(geo.Position position) {
    if (!position.hasAltitude) {
      return 'Altitude système : indisponible';
    }

    final altitude = position.altitude.toStringAsFixed(1);

    if (!position.hasAltitudeAccuracy || position.altitudeAccuracy <= 0) {
      return 'Altitude système : $altitude m '
          '(précision inconnue)';
    }

    return 'Altitude système : $altitude m '
        '(±${position.altitudeAccuracy.toStringAsFixed(1)} m)';
  }

  String _locationStatus() {
    if (_isLocating) {
      return 'Recherche de la position GPS…';
    }

    if (_locationError != null) {
      return _locationError!;
    }

    final position = _position;

    if (position == null) {
      return 'Position GPS indisponible.';
    }

    return 'Latitude : ${formatDms(position.latitude, isLatitude: true)}\n'
        'Longitude : ${formatDms(position.longitude, isLatitude: false)}\n'
        'Précision : ±${position.accuracy.toStringAsFixed(1)} m\n'
        '${_altitudeStatus(position)}';
  }

  @override
  void dispose() {
    _orientationSubscription?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(title: const Text('Prototype caméra')),
      body: Center(
        child: _cameraError != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_cameraError!, textAlign: TextAlign.center),
              )
            : controller == null || !controller.value.isInitialized
            ? const CircularProgressIndicator()
            : Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(controller),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: SafeArea(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(_locationStatus())),
                                  IconButton(
                                    onPressed: _isLocating
                                        ? null
                                        : _loadPosition,
                                    tooltip: 'Actualiser la position',
                                    icon: const Icon(Icons.refresh),
                                  ),
                                ],
                              ),
                              const Divider(),
                              Text(_orientationStatus()),
                              const SizedBox(height: 8),
                              Text(_captureRequirementStatus()),
                              if (_captureStatus != null) ...[
                                const SizedBox(height: 8),
                                Text(_captureStatus!),
                              ],
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _canCapture ? _capturePhoto : null,
                                icon: _isCapturing
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.camera_alt),
                                label: const Text('Capturer'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
