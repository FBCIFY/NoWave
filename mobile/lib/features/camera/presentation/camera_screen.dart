import 'dart:async';
import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:precise_compass/precise_compass.dart';

import '../../../core/location/location_service.dart';
import '../../../core/sensors/device_orientation_service.dart';
import '../../../core/sensors/camera_orientation.dart';
import '../domain/capture_requirements.dart';
import '../domain/photo_capture.dart';
import '../domain/report_jpeg.dart';

/// Photo d'un signalement (NW-115), ouverte depuis la carte : aperçu caméra
/// plein écran, réticule central, position GPS et orientation du téléphone.
///
/// La photo n'est autorisée qu'avec une précision GPS d'au plus 50 m et une
/// orientation complète (cap, tangage, roulis). Les mesures sont figées au
/// moment de l'appui ; la photo reste en mémoire tant que l'écran est ouvert.
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
  bool _locationNeedsSettings = false;
  StreamSubscription<geo.Position>? _positionSubscription;
  CameraController? _controller;
  String? _cameraError;
  bool _isCapturing = false;
  String? _captureError;
  PhotoCapture? _capture;
  StreamSubscription<CompassReading>? _orientationSubscription;
  CompassReading? _orientation;
  String? _orientationError;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // L'aperçu plein écran et le calcul de l'inclinaison supposent le portrait.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initializeCamera();
    _listenToPosition();
    _listenToOrientation();
    _lifecycleListener = AppLifecycleListener(
      onResume: _retryLocationIfBlocked,
    );
  }

  /// Au retour des réglages (ou si le GPS a décroché), relance la position
  /// sans que l'utilisateur ait à rouvrir la caméra.
  void _retryLocationIfBlocked() {
    if (_isLocating || _locationError == null) return;

    _positionSubscription?.cancel();
    _positionSubscription = null;
    _listenToPosition();
  }

  /// Première position (avec demande d'autorisation), puis suivi continu :
  /// la position figée à la photo est toujours récente, même en route.
  Future<void> _listenToPosition() async {
    setState(() {
      _isLocating = true;
      _locationError = null;
      _locationNeedsSettings = false;
    });

    try {
      final position = await _locationService.getCurrentPosition();

      if (!mounted) return;

      setState(() {
        _position = position;
      });

      _positionSubscription =
          geo.Geolocator.getPositionStream(
            locationSettings: const geo.LocationSettings(
              accuracy: geo.LocationAccuracy.high,
            ),
          ).listen(
            (position) {
              if (!mounted) return;

              setState(() {
                _position = position;
                _locationError = null;
              });
            },
            onError: (Object _) {
              if (!mounted) return;

              setState(() {
                _locationError = 'Position GPS indisponible pour le moment.';
              });
            },
          );
    } on StateError catch (error) {
      if (!mounted) return;

      setState(() {
        _locationError = error.message;
        _locationNeedsSettings = true;
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
        // 1920 × 1080 : assez net pour reconnaître l'objet une fois réduit.
        ResolutionPreset.veryHigh,
        enableAudio: false,
      );

      _controller = controller;
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      // L'interface reste en portrait : sans ce verrou, le plugin tourne
      // l'aperçu quand on met le téléphone à l'horizontale.
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);

      if (!mounted) return;

      setState(() {});
    } on CameraException catch (error) {
      if (!mounted) return;

      setState(() {
        _cameraError = _cameraErrorMessage(error);
      });
    }
  }

  /// Ce qui empêche encore la photo, ou `null` si tout est prêt.
  String? _blockingReason() {
    if (_isLocating) {
      return 'Recherche de la position GPS…';
    }

    if (_locationError != null) {
      return _locationError;
    }

    final position = _position;

    if (position == null) {
      return 'Position GPS indisponible.';
    }

    if (!isCaptureGpsAccuracySufficient(position.accuracy)) {
      return 'Précision GPS insuffisante : '
          '±${position.accuracy.toStringAsFixed(0)} m '
          '(${maxCaptureGpsAccuracyMeters.toStringAsFixed(0)} m max).';
    }

    if (_orientationError != null) {
      return _orientationError;
    }

    final orientation = _orientation;

    if (orientation == null ||
        orientation.headingTrue == null ||
        orientation.pitch == null ||
        orientation.roll == null) {
      return 'Recherche de l’orientation…';
    }

    return null;
  }

  bool get _canCapture {
    final controller = _controller;

    return controller != null &&
        controller.value.isInitialized &&
        !_isCapturing &&
        _blockingReason() == null;
  }

  Future<void> _capturePhoto() async {
    final controller = _controller;
    final position = _position;
    final heading = _orientation?.headingTrue;
    final pitch = _orientation?.pitch;
    final roll = _orientation?.roll;

    if (!_canCapture ||
        controller == null ||
        position == null ||
        heading == null ||
        pitch == null ||
        roll == null) {
      return;
    }

    // Figées avant takePicture : c'est ce que l'utilisateur vise à l'appui.
    final measurements = PhotoCaptureMeasurements(
      observerLongitude: position.longitude,
      observerLatitude: position.latitude,
      gpsAccuracyMeters: position.accuracy,
      azimuthDegrees: heading,
      inclinationDegrees: calculateCameraInclinationDegrees(
        pitchDegrees: pitch,
        rollDegrees: roll,
      ),
      cameraHeightMeters: defaultCameraHeightMeters,
      cameraHeightSource: defaultCameraHeightSource,
      cameraHeightUncertaintyMeters: defaultCameraHeightUncertaintyMeters,
      capturedAt: DateTime.now(),
    );

    setState(() {
      _isCapturing = true;
      _captureError = null;
    });

    try {
      final photo = await controller.takePicture();
      final originalBytes = await photo.readAsBytes();
      await _deleteOriginalPhoto(photo.path);
      // compute avec une fonction de haut niveau : une closure créée ici
      // emporterait l'écran (this) vers l'autre isolate, ce qui est interdit.
      final jpegBytes = await compute(prepareReportJpeg, originalBytes);

      if (!mounted) return;

      setState(() {
        _capture = PhotoCapture(
          jpegBytes: jpegBytes,
          measurements: measurements,
        );
      });
    } on CameraException {
      if (!mounted) return;

      setState(() {
        _captureError = 'Impossible de prendre la photo.';
      });
    } on FormatException {
      if (!mounted) return;

      setState(() {
        _captureError = 'Photo inutilisable. Reprenez-la.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  /// L'original garde la position GPS dans ses EXIF : seule la version
  /// nettoyée reste, en mémoire.
  Future<void> _deleteOriginalPhoto(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // Fichier temporaire de l'app : le système finira par le supprimer.
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

  String _measuresText({
    required double accuracyMeters,
    required double headingDegrees,
    required double inclinationDegrees,
  }) {
    return '±${accuracyMeters.toStringAsFixed(0)} m · '
        'cap ${headingDegrees.toStringAsFixed(0)}° · '
        'inclinaison ${inclinationDegrees.toStringAsFixed(0)}°';
  }

  String _liveStatus() {
    final blockingReason = _blockingReason();

    if (blockingReason != null) {
      return blockingReason;
    }

    final position = _position!;
    final orientation = _orientation!;
    final measures = _measuresText(
      accuracyMeters: position.accuracy,
      headingDegrees: orientation.headingTrue!,
      inclinationDegrees: calculateCameraInclinationDegrees(
        pitchDegrees: orientation.pitch!,
        rollDegrees: orientation.roll!,
      ),
    );

    if (orientation.shouldCalibrate) {
      return '$measures\n'
          'Calibrez la boussole : dessinez un 8 avec le téléphone.';
    }

    return measures;
  }

  String? _lastCaptureStatus() {
    if (_captureError != null) {
      return _captureError;
    }

    final capture = _capture;

    if (capture == null) {
      return null;
    }

    final measurements = capture.measurements;
    final sizeKilobytes = (capture.jpegBytes.length / 1000).round();

    final measures = _measuresText(
      accuracyMeters: measurements.gpsAccuracyMeters,
      headingDegrees: measurements.azimuthDegrees,
      inclinationDegrees: measurements.inclinationDegrees,
    );

    return 'Photo prise ($sizeKilobytes Ko) : $measures';
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const []);
    _lifecycleListener.dispose();
    _positionSubscription?.cancel();
    _orientationSubscription?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final capture = _capture;
    final lastCaptureStatus = _lastCaptureStatus();
    final overlayButtonStyle = IconButton.styleFrom(
      backgroundColor: Colors.black45,
      foregroundColor: Colors.white,
      disabledBackgroundColor: Colors.black26,
      disabledForegroundColor: Colors.white38,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_cameraError != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _cameraError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              )
            else if (controller == null || !controller.value.isInitialized)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            else ...[
              _FullScreenPreview(controller: controller),
              const _Reticle(),
            ],
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: 'Fermer',
                      onPressed: () => Navigator.of(context).pop(),
                      style: overlayButtonStyle,
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Text(
                            lastCaptureStatus == null
                                ? _liveStatus()
                                : '${_liveStatus()}\n$lastCaptureStatus',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                      if (_locationNeedsSettings) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: AppSettings.openAppSettings,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Ouvrir les réglages'),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 76,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            _ShutterButton(
                              onPressed: _canCapture ? _capturePhoto : null,
                              isBusy: _isCapturing,
                            ),
                            if (capture != null)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    capture.jpegBytes,
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
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

/// Aperçu recadré pour remplir l'écran. Le recadrage est centré : le réticule
/// vise le centre de la photo, qui montre un peu plus que l'aperçu.
class _FullScreenPreview extends StatelessWidget {
  const _FullScreenPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;

    if (previewSize == null) {
      return CameraPreview(controller);
    }

    // previewSize est donné en paysage : largeur et hauteur sont inversées.
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewSize.height,
          height: previewSize.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

/// Réticule central : l'objet signalé doit être visé au centre de l'image.
class _Reticle extends StatelessWidget {
  const _Reticle();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.onPressed, required this.isBusy});

  final VoidCallback? onPressed;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Prendre la photo',
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 76,
          height: 76,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled ? Colors.white : Colors.white38,
            ),
            child: isBusy
                ? const Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
