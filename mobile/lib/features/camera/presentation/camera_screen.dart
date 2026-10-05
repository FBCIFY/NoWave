import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:precise_compass/precise_compass.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/location/location_service.dart';
import '../../../core/sensors/camera_inclination_service.dart';
import '../../../core/sensors/device_orientation_service.dart';
import '../data/position_estimate_service.dart';
import '../domain/capture_requirements.dart';
import '../domain/photo_capture.dart';
import '../domain/photo_report_draft.dart';
import '../domain/report_jpeg.dart';
import 'report_camera.dart';

/// Photo d'un signalement (NW-115), ouverte depuis la carte : aperçu caméra
/// plein écran, réticule central, position GPS et orientation du téléphone.
///
/// La photo n'est autorisée qu'avec une précision GPS d'au plus 50 m et une
/// orientation complète (cap et inclinaison). Les mesures sont figées au
/// moment de l'appui ; la photo reste en mémoire tant que l'écran est ouvert.
///
/// « Continuer » demande l'estimation au backend puis ferme l'écran en
/// renvoyant un [PhotoReportDraft] à la carte.
///
/// Caméra, GPS et capteurs sont injectables pour les tests ; par défaut,
/// ceux du téléphone. L'écran libère la caméra en se fermant.
class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.positionEstimateService,
    this.camera,
    this.locationService,
    this.orientationService,
    this.inclinationService,
  });

  final PositionEstimateService positionEstimateService;
  final ReportCamera? camera;
  final LocationService? locationService;
  final DeviceOrientationService? orientationService;
  final CameraInclinationService? inclinationService;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late final _camera = widget.camera ?? DeviceReportCamera();
  late final _locationService = widget.locationService ?? LocationService();
  late final _orientationService =
      widget.orientationService ?? DeviceOrientationService();
  late final _inclinationService =
      widget.inclinationService ?? CameraInclinationService();

  geo.Position? _position;
  bool _isLocating = false;
  String? _locationError;
  bool _locationNeedsSettings = false;
  StreamSubscription<geo.Position>? _positionSubscription;
  bool _isCameraReady = false;
  String? _cameraError;
  bool _isCapturing = false;
  String? _captureError;
  PhotoCapture? _capture;
  bool _isEstimating = false;
  StreamSubscription<CompassReading>? _orientationSubscription;
  CompassReading? _orientation;
  String? _orientationError;
  StreamSubscription<double>? _inclinationSubscription;
  double? _inclinationDegrees;
  String? _inclinationError;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // L'aperçu plein écran suppose le portrait.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initializeCamera();
    _listenToPosition();
    _listenToOrientation();
    _listenToInclination();
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

      _positionSubscription = _locationService.watchPosition().listen(
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

  void _listenToInclination() {
    _inclinationSubscription = _inclinationService.inclinationDegrees.listen(
      (inclination) {
        if (!mounted) return;

        // ~50 mesures par seconde : on garde toujours la dernière pour la
        // capture, mais on ne redessine que si le degré affiché change.
        if (_inclinationError == null &&
            _inclinationDegrees?.round() == inclination.round()) {
          _inclinationDegrees = inclination;
          return;
        }

        setState(() {
          _inclinationDegrees = inclination;
          _inclinationError = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;

        setState(() {
          _inclinationError = 'Inclinomètre indisponible.';
        });
      },
    );
  }

  Future<void> _initializeCamera() async {
    try {
      await _camera.initialize();

      if (!mounted) return;

      setState(() {
        _isCameraReady = true;
      });
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

    if (_inclinationError != null) {
      return _inclinationError;
    }

    if (_orientation?.headingTrue == null || _inclinationDegrees == null) {
      return 'Recherche de l’orientation…';
    }

    return null;
  }

  bool get _canCapture {
    return _isCameraReady &&
        !_isCapturing &&
        !_isEstimating &&
        _blockingReason() == null;
  }

  Future<void> _capturePhoto() async {
    final position = _position;
    final heading = _orientation?.headingTrue;
    final inclination = _inclinationDegrees;

    if (!_canCapture ||
        position == null ||
        heading == null ||
        inclination == null) {
      return;
    }

    // Figées avant takePicture : c'est ce que l'utilisateur vise à l'appui.
    final measurements = PhotoCaptureMeasurements(
      observerLongitude: position.longitude,
      observerLatitude: position.latitude,
      gpsAccuracyMeters: position.accuracy,
      azimuthDegrees: heading,
      inclinationDegrees: inclination,
      cameraHeightMeters: defaultCameraHeightMeters,
      cameraHeightSource: defaultCameraHeightSource,
      cameraHeightUncertaintyMeters: defaultCameraHeightUncertaintyMeters,
      capturedAt: DateTime.now(),
    );

    AppHaptics.capture();
    setState(() {
      _isCapturing = true;
      _captureError = null;
    });

    try {
      final originalBytes = await _camera.takePicture();
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

  void _retakePhoto() {
    if (_isEstimating) return;

    setState(() {
      _capture = null;
      _captureError = null;
    });
  }

  Future<void> _continueWithCapture() async {
    final capture = _capture;

    if (capture == null || _isCapturing || _isEstimating) return;

    setState(() {
      _isEstimating = true;
      _captureError = null;
    });

    try {
      final estimate = await widget.positionEstimateService.estimate(
        capture.measurements,
      );

      if (!mounted) return;

      Navigator.of(context)
          .pop(PhotoReportDraft(capture: capture, estimate: estimate));
    } on ApiException catch (error) {
      if (!mounted) return;

      setState(() {
        _captureError = _estimateErrorMessage(error);
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _captureError = 'Estimation impossible. Vérifiez votre connexion.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isEstimating = false;
        });
      }
    }
  }

  String _estimateErrorMessage(ApiException error) {
    if (error.statusCode == 422) {
      if (error.code == 'gps_precision_insufficient') {
        return 'Précision GPS insuffisante. Reprenez la photo.';
      }

      return 'Mesures refusées. Reprenez la photo.';
    }

    return switch (error.statusCode) {
      401 => 'Votre session a expiré. Reconnectez-vous.',
      403 => 'Votre compte ne peut pas publier de signalement.',
      404 => 'Estimation indisponible sur ce serveur.',
      _ => 'Estimation impossible. Réessayez.',
    };
  }

  String _cameraErrorMessage(CameraException error) {
    return switch (error.code) {
      ReportCamera.noCameraCode => 'Aucune caméra disponible sur cet appareil.',
      ReportCamera.noBackCameraCode =>
        'Aucune caméra arrière disponible sur cet appareil.',
      'CameraAccessDenied' ||
      'CameraAccessDeniedWithoutPrompt' ||
      'CameraAccessRestricted' =>
        'L’accès à la caméra est refusé. '
            'Autorisez-le dans les réglages du téléphone.',
      _ => 'Impossible d’ouvrir la caméra.',
    };
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
      inclinationDegrees: _inclinationDegrees!,
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
    _inclinationSubscription?.cancel();
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            else if (!_isCameraReady)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            else ...[
              // Photo prise : on la montre figée à la place de l'aperçu, pour
              // vérifier ce qui a été visé avant de continuer.
              if (capture != null)
                Image.memory(
                  capture.jpegBytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                )
              else
                _camera.buildPreview(),
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
                            capture != null
                                ? lastCaptureStatus!
                                : lastCaptureStatus == null
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
                        child: capture == null
                            ? Center(
                                child: _ShutterButton(
                                  onPressed: _canCapture ? _capturePhoto : null,
                                  isBusy: _isCapturing,
                                ),
                              )
                            : _CaptureActions(
                                isEstimating: _isEstimating,
                                onRetake: _retakePhoto,
                                onContinue: _continueWithCapture,
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

/// Après la prise : reprendre la photo ou l'envoyer pour estimation. Le
/// déclencheur est masqué pour qu'aucun bouton ne se superpose.
class _CaptureActions extends StatelessWidget {
  const _CaptureActions({
    required this.isEstimating,
    required this.onRetake,
    required this.onContinue,
  });

  final bool isEstimating;
  final VoidCallback onRetake;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    const buttonSize = Size.fromHeight(52);

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isEstimating ? null : onRetake,
            style: OutlinedButton.styleFrom(
              minimumSize: buttonSize,
              foregroundColor: Colors.white,
              backgroundColor: Colors.black45,
              disabledForegroundColor: Colors.white38,
              side: const BorderSide(color: Colors.white70),
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('Reprendre'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: isEstimating ? null : onContinue,
            style: FilledButton.styleFrom(
              minimumSize: buttonSize,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              disabledBackgroundColor: Colors.white70,
              disabledForegroundColor: Colors.black54,
            ),
            child: isEstimating
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black54,
                    ),
                  )
                : const Text('Continuer'),
          ),
        ),
      ],
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
