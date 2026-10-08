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
import '../../../core/sensors/camera_axis_service.dart';
import '../../../core/sensors/camera_azimuth.dart';
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
/// renvoyant un [PhotoReportDraft] à la carte. Si le service d'estimation est
/// en panne, « Placer le point moi-même » renvoie la photo sans estimation :
/// la carte demande alors le point (NW-156).
///
/// Caméra, GPS et capteurs sont injectables pour les tests ; par défaut,
/// ceux du téléphone. L'écran libère la caméra en se fermant et quand
/// l'application passe en arrière-plan, puis la rouvre au retour.
class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.positionEstimateService,
    this.createCamera,
    this.locationService,
    this.orientationService,
    this.inclinationService,
    this.cameraAxisService,
  });

  final PositionEstimateService positionEstimateService;

  /// Crée une caméra neuve à chaque ouverture : une caméra libérée ne se
  /// rouvre pas.
  final ReportCamera Function()? createCamera;
  final LocationService? locationService;
  final DeviceOrientationService? orientationService;
  final CameraInclinationService? inclinationService;

  /// Axe de visée, sur Android uniquement. Par défaut, le capteur du
  /// téléphone sur Android et rien sur iOS.
  final CameraAxisService? cameraAxisService;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  /// Null quand la caméra est libérée (écran masqué).
  ReportCamera? _camera;

  /// L'écran est visible et veut une caméra.
  bool _isCameraWanted = false;

  /// Libération de la dernière caméra fermée.
  Future<void> _cameraRelease = Future.value();
  late final _locationService = widget.locationService ?? LocationService();
  late final _orientationService =
      widget.orientationService ?? DeviceOrientationService();
  late final _inclinationService =
      widget.inclinationService ?? CameraInclinationService();
  late final _cameraAxisService =
      widget.cameraAxisService ??
      (defaultTargetPlatform == TargetPlatform.android
          ? CameraAxisService()
          : null);

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

  /// L'estimation est en panne : la photo peut partir sans elle.
  bool _canPlacePointManually = false;
  StreamSubscription<CompassReading>? _orientationSubscription;
  CompassReading? _orientation;
  String? _orientationError;
  StreamSubscription<double>? _inclinationSubscription;
  double? _inclinationDegrees;
  String? _inclinationError;
  StreamSubscription<CameraAxis>? _cameraAxisSubscription;
  CameraAxis? _cameraAxis;
  String? _cameraAxisError;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // L'aperçu plein écran suppose le portrait.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _openCamera();
    _listenToPosition();
    _listenToOrientation();
    _listenToInclination();
    _listenToCameraAxis();
    _lifecycleListener = AppLifecycleListener(
      onResume: _retryLocationIfBlocked,
      // Écran verrouillé ou autre application : le système peut reprendre
      // la caméra, on la libère et on en rouvre une au retour.
      onHide: _closeCamera,
      onShow: _openCamera,
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

  /// Azimut vrai de la caméra. Sur Android, le cap de `precise_compass` suit
  /// le haut du téléphone et non la caméra : on le recalcule depuis l'axe de
  /// visée (NW-150). Sur iOS, on garde le cap de CoreLocation.
  double? get _cameraHeading {
    final orientation = _orientation;
    if (orientation == null) return null;
    if (_cameraAxisService == null) return orientation.headingTrue;
    final axis = _cameraAxis;
    if (axis == null) return null;
    return cameraTrueAzimuthDegrees(
      axis: axis,
      headingMagnetic: orientation.headingMagnetic,
      headingTrue: orientation.headingTrue,
    );
  }

  bool get _isAimingVertically {
    final axis = _cameraAxis;
    return axis != null && cameraAzimuthDegrees(axis) == null;
  }

  void _listenToCameraAxis() {
    final service = _cameraAxisService;
    if (service == null) return;

    _cameraAxisSubscription = service.axis.listen(
      (axis) {
        if (!mounted) return;

        // ~50 mesures par seconde : on ne redessine que si le degré affiché
        // ou le message change.
        final before = (_cameraHeading?.round(), _isAimingVertically);
        _cameraAxis = axis;
        if (_cameraAxisError == null &&
            before == (_cameraHeading?.round(), _isAimingVertically)) {
          return;
        }

        setState(() => _cameraAxisError = null);
      },
      onError: (Object error) {
        if (!mounted) return;

        setState(() {
          _cameraAxisError = 'Capteurs d’orientation indisponibles.';
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

  Future<void> _openCamera() async {
    if (_isCameraWanted) return;
    _isCameraWanted = true;

    // Le système refuse deux caméras ouvertes : la nouvelle attend que la
    // précédente soit rendue.
    await _cameraRelease;

    // Masqué de nouveau entre-temps, ou une autre ouverture est passée avant.
    if (!mounted || !_isCameraWanted || _camera != null) return;

    final camera = (widget.createCamera ?? DeviceReportCamera.new)();
    _camera = camera;
    _initializeCamera(camera);
  }

  void _closeCamera() {
    _isCameraWanted = false;
    final camera = _camera;
    if (camera == null) return;

    _camera = null;
    _cameraRelease = camera.dispose().catchError((Object _) {
      // Libération ratée : rien de plus à faire, la suivante tentera sa
      // chance.
    });
    setState(() {
      _isCameraReady = false;
      _cameraError = null;
    });
  }

  Future<void> _initializeCamera(ReportCamera camera) async {
    try {
      await camera.initialize();

      // Écran fermé ou masqué entre-temps : cette caméra est déjà libérée.
      if (!mounted || camera != _camera) return;

      setState(() {
        _isCameraReady = true;
      });
    } on CameraException catch (error) {
      if (!mounted || camera != _camera) return;

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

    if (_cameraAxisError != null) {
      return _cameraAxisError;
    }

    if (_isAimingVertically) {
      return 'Relevez le téléphone vers l’horizon.';
    }

    if (_cameraHeading == null || _inclinationDegrees == null) {
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
    final camera = _camera;
    final position = _position;
    final heading = _cameraHeading;
    final inclination = _inclinationDegrees;

    if (!_canCapture ||
        camera == null ||
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
      // Aucun zoom numérique n'est appliqué par l'application.
      zoomRatio: 1,
    );

    AppHaptics.capture();
    setState(() {
      _isCapturing = true;
      _captureError = null;
    });

    try {
      final originalBytes = await camera.takePicture();
      final focalLengthMm = readFocalLengthMm(originalBytes);
      // compute avec une fonction de haut niveau : une closure créée ici
      // emporterait l'écran (this) vers l'autre isolate, ce qui est interdit.
      final jpegBytes = await compute(prepareReportJpeg, originalBytes);

      if (!mounted) return;

      setState(() {
        _capture = PhotoCapture(
          jpegBytes: jpegBytes,
          measurements: measurements.withFocalLength(focalLengthMm),
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
      _canPlacePointManually = false;
    });
  }

  Future<void> _continueWithCapture() async {
    final capture = _capture;

    if (capture == null || _isCapturing || _isEstimating) return;

    setState(() {
      _isEstimating = true;
      _captureError = null;
      _canPlacePointManually = false;
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
        _canPlacePointManually = _isEstimateOutage(error);
      });
    } catch (_) {
      // Pas de réseau, délai dépassé ou réponse illisible.
      if (!mounted) return;

      setState(() {
        _captureError = 'Estimation impossible. Vérifiez votre connexion.';
        _canPlacePointManually = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isEstimating = false;
        });
      }
    }
  }

  /// Le service est en panne ou absent : le point manuel reste possible.
  /// Session expirée, compte bloqué ou mesures refusées ne s'arrangent pas
  /// en plaçant le point soi-même.
  bool _isEstimateOutage(ApiException error) {
    final status = error.statusCode;
    return status == 404 || status == 429 || status >= 500;
  }

  /// Renvoie la photo sans estimation : la carte demande le point.
  void _placePointManually() {
    final capture = _capture;
    if (capture == null || _isEstimating) return;

    Navigator.of(context)
        .pop(PhotoReportDraft(capture: capture, estimate: null));
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
      headingDegrees: _cameraHeading!,
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
    _cameraAxisSubscription?.cancel();
    _camera?.dispose();
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
            // Photo prise : on la montre figée à la place de l'aperçu, pour
            // vérifier ce qui a été visé avant de continuer. Elle reste
            // affichée pendant que la caméra se rouvre après l'arrière-plan.
            if (capture != null) ...[
              Image.memory(
                capture.jpegBytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
              const _Reticle(),
            ] else if (_cameraError != null)
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
              _camera!.buildPreview(),
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
                      if (capture != null && _canPlacePointManually) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _isEstimating ? null : _placePointManually,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Placer le point moi-même'),
                        ),
                      ],
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
