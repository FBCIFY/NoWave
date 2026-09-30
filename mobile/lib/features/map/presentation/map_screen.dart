import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:geolocator/geolocator.dart' as geo;
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:precise_compass/precise_compass.dart';
import 'package:uuid/uuid.dart';

import '../../../core/map/map_config.dart';
import '../../../core/location/coordinate_formatter.dart';
import '../../../core/location/location_service.dart';
import '../../../core/sensors/device_orientation_service.dart';
import '../../reports/presentation/report_composer_sheet.dart';
import '../../reports/data/manual_report_service.dart';
import '../../reports/domain/manual_report.dart';

/// Nord en haut, carte tournée selon le cap du téléphone, ou rotation libre
/// faite au doigt.
enum _MapOrientationMode { north, heading, manual }

/// Carte principale : position GPS, suivi de l'utilisateur, boussole et
/// création d'un signalement.
///
/// En mode signalement, le marqueur reste fixe à l'écran et c'est la carte
/// qu'on déplace dessous ; le point visé est recalculé à chaque mouvement.
class MapScreen extends StatefulWidget {
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenCamera;
  final ManualReportService? reportService;

  const MapScreen({
    super.key,
    this.onOpenProfile,
    this.onOpenCamera,
    this.reportService,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _locationService = LocationService();
  StreamSubscription<geo.Position>? _positionSubscription;
  StreamSubscription<CompassReading>? _headingSubscription;

  geo.Position? _position;
  double? _deviceHeading;
  double? _selectedBearing;
  double _cameraBearing = 0;
  double _compassTurns = 0;
  bool _isFollowing = false;
  bool _mapTouchActive = false;
  double _touchStartBearing = 0;
  _MapOrientationMode _orientationMode = _MapOrientationMode.north;
  bool _isLocating = false;
  String? _locationError;
  MapboxMap? _mapboxMap;
  String? _mapError;
  bool _reportComposerOpen = false;
  CameraState? _cameraBeforeReport;
  bool _restoreFollowAfterReport = false;
  final ValueNotifier<Point?> _reportPoint = ValueNotifier(null);
  final Uuid _uuid = const Uuid();
  ManualReportRequest? _pendingReport;
  Timer? _reportPointTimer;
  int _reportPointRequest = 0;
  final _mapAreaKey = GlobalKey();
  final _reportMarkerKey = GlobalKey();
  bool _wasKeyboardVisible = false;

  @override
  void initState() {
    super.initState();
    _headingSubscription = DeviceOrientationService().readings.listen(
      (reading) {
        if (!mounted) return;
        final heading = reading.headingTrue ?? reading.headingMagnetic;
        if (heading == null || !heading.isFinite) return;
        _deviceHeading = heading;
        _setCompassTurnsForHeading(heading);
      },
      onError: (Object _) {
        _deviceHeading = null;
      },
    );
  }

  void _setCompassTurnsForHeading(double heading) {
    final displayedHeading = (_compassTurns * 360) % 360;
    final change = (heading - displayedHeading + 540) % 360 - 180;
    if (change.abs() < 1) return;
    setState(() => _compassTurns += change / 360);
  }

  // Un geste de l'utilisateur coupe le suivi GPS ; une rotation au doigt
  // passe la boussole en mode manuel.
  void _handleMapCameraChange(CameraChangedEventData event) {
    final bearing = event.cameraState.bearing;
    final bearingDelta = ((bearing - _cameraBearing + 540) % 360 - 180);
    final userMovedMap = _mapTouchActive && _isFollowing;
    final touchBearingDelta =
        ((bearing - _touchStartBearing + 540) % 360 - 180);
    final userRotatedMap = _mapTouchActive && touchBearingDelta.abs() > 2;
    if (bearingDelta.abs() >= 1) _cameraBearing = bearing;
    if (_reportComposerOpen) {
      _scheduleReportPointUpdate();
      return;
    }
    if (!userMovedMap && !userRotatedMap) return;

    setState(() {
      _isFollowing = false;
      if (userRotatedMap) _orientationMode = _MapOrientationMode.manual;
    });
  }

  void _handleMapGesture(MapContentGestureContext _) {
    if (_reportComposerOpen) return;
    if (!_isFollowing) return;
    setState(() => _isFollowing = false);
  }

  Future<void> _positionMapOrnaments(
    MapboxMap map, {
    required bool editing,
  }) async {
    try {
      await Future.wait([
        map.logo.updateSettings(
          LogoSettings(
            position: editing
                ? OrnamentPosition.TOP_LEFT
                : OrnamentPosition.BOTTOM_LEFT,
            marginLeft: 16,
            marginTop: editing ? 64 : 4,
            marginBottom: 4,
          ),
        ),
        map.attribution.updateSettings(
          AttributionSettings(
            position: editing
                ? OrnamentPosition.TOP_RIGHT
                : OrnamentPosition.BOTTOM_RIGHT,
            marginRight: 16,
            marginTop: editing ? 64 : 4,
            marginBottom: 4,
          ),
        ),
      ]);
    } catch (_) {
      // Keep Mapbox's default placement if ornament settings are unavailable.
    }
  }

  // Bascule entre nord en haut et cap du téléphone.
  Future<void> _toggleCompass() async {
    final map = _mapboxMap;
    if (map == null) return;
    final previousMode = _orientationMode;
    final previousSelectedBearing = _selectedBearing;
    final nextMode = _orientationMode == _MapOrientationMode.north
        ? _MapOrientationMode.heading
        : _MapOrientationMode.north;
    final heading = _deviceHeading;
    if (nextMode == _MapOrientationMode.heading && heading == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cap du téléphone indisponible.')),
      );
      return;
    }
    final targetBearing = nextMode == _MapOrientationMode.north
        ? 0.0
        : heading!;

    try {
      if (_isFollowing) {
        final camera = await map.getCameraState();
        if (!mounted) return;
        // Mapbox marks this animated viewport helper as experimental.
        // ignore: experimental_member_use
        setStateWithViewportAnimation(() {
          _orientationMode = nextMode;
          _selectedBearing = targetBearing;
          _viewport = FollowPuckViewportState(
            zoom: camera.zoom,
            pitch: camera.pitch,
            bearing: FollowPuckViewportStateBearingConstant(targetBearing),
          );
        });
      } else {
        setState(() {
          _orientationMode = nextMode;
          _selectedBearing = targetBearing;
        });
        await map.easeTo(
          CameraOptions(bearing: targetBearing),
          MapAnimationOptions(duration: 350),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _orientationMode = previousMode;
        _selectedBearing = previousSelectedBearing;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de changer l’orientation.')),
      );
    }
  }

  void _handleMapLoadError(MapLoadingErrorEventData event) {
    if (!mounted) return;

    setState(() {
      _mapError = 'Impossible de charger la carte. Vérifiez votre connexion et réessayez.';
    });
  }

  void _handleMapLoaded(MapLoadedEventData event) {
    if (!mounted || _mapError == null) return;
    setState(() => _mapError = null);
  }

  Future<void> _retryMapLoad() async {
    final map = _mapboxMap;

    if (map == null) return;

    setState(() {
      _mapError = null;
    });

    try {
      await map.loadStyleURI(MapConfig.styleUrl);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _mapError = 'Impossible de charger la carte. Vérifiez votre connexion et réessayez.';
      });
    }
  }

  // Centre la carte sur l'utilisateur puis le suit à chaque nouvelle position.
  Future<void> _locate() async {
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

      await _mapboxMap?.location.updateSettings(
        LocationComponentSettings(enabled: true),
      );

      if (!mounted) return;

      CameraState? previousCamera;
      if (_positionSubscription != null) {
        try {
          previousCamera = await _mapboxMap?.getCameraState();
        } catch (_) {
          // The default camera values below remain available.
        }
      }

      if (!mounted) return;

      setState(() {
        _isFollowing = true;
        _viewport = FollowPuckViewportState(
          zoom: previousCamera?.zoom ?? 14,
          bearing: switch (_orientationMode) {
            _MapOrientationMode.north =>
              const FollowPuckViewportStateBearingConstant(0),
            _MapOrientationMode.heading =>
              FollowPuckViewportStateBearingConstant(
                _selectedBearing ?? previousCamera?.bearing ?? _cameraBearing,
              ),
            _MapOrientationMode.manual =>
              FollowPuckViewportStateBearingConstant(
                previousCamera?.bearing ?? _cameraBearing,
              ),
          },
          pitch: previousCamera?.pitch ?? 60,
        );
      });

      _positionSubscription ??=
          geo.Geolocator.getPositionStream(
            locationSettings: const geo.LocationSettings(
              accuracy: geo.LocationAccuracy.high,
              distanceFilter: 10,
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
                _locationError = 'Position indisponible pour le moment.';
              });
            },
            onDone: () {
              _positionSubscription = null;
            },
          );
    } on StateError catch (error) {
      if (!mounted) return;

      setState(() {
        _locationError = error.message;
      });
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _locationError = 'Position introuvable pour le moment. Réessayez.';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _locationError = 'Impossible de récupérer votre position.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  // Ouvre le formulaire et mémorise la caméra pour la rétablir à la fermeture.
  Future<void> _openReportComposer() async {
    if (_reportComposerOpen) return;
    final position = _position;
    final map = _mapboxMap;
    if (position == null || map == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Attendez que votre position GPS soit disponible.'),
        ),
      );
      return;
    }

    CameraState camera;
    try {
      camera = await map.getCameraState();
    } catch (_) {
      return;
    }
    if (!mounted) return;

    setState(() {
      _cameraBeforeReport = camera;
      _restoreFollowAfterReport = _isFollowing;
      _reportComposerOpen = true;
      _pendingReport = null;
      _isFollowing = false;
      _reportPoint.value = Point(
        coordinates: Position(position.longitude, position.latitude),
      );
      _viewport = CameraViewportState(
        center: camera.center,
        zoom: camera.zoom,
        pitch: camera.pitch,
        bearing: camera.bearing,
      );
    });
    unawaited(_positionMapOrnaments(map, editing: true));
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_reportComposerOpen) return;
    final reportPadding = _reportCameraPadding();
    try {
      await map.easeTo(
        CameraOptions(
          center: Point(
            coordinates: Position(position.longitude, position.latitude),
          ),
          zoom: 14,
          pitch: 0,
          bearing: 0,
          padding: reportPadding,
        ),
        MapAnimationOptions(duration: 350),
      );
    } catch (_) {
      // The report can still be placed by moving the existing map.
    }
    _scheduleReportPointUpdate();
  }

  Future<void> _closeReportComposer() async {
    if (!_reportComposerOpen) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _reportPointTimer?.cancel();
    _reportPointRequest++;
    final camera = _cameraBeforeReport;
    final map = _mapboxMap;
    final resumeFollowing = _restoreFollowAfterReport;
    setState(() {
      _reportComposerOpen = false;
      _reportPoint.value = null;
      _pendingReport = null;
      _restoreFollowAfterReport = false;
    });
    if (map != null) unawaited(_positionMapOrnaments(map, editing: false));

    if (map != null && camera != null) {
      try {
        await map.easeTo(
          CameraOptions(
            center: camera.center,
            zoom: camera.zoom,
            pitch: camera.pitch,
            bearing: camera.bearing,
            padding: camera.padding,
          ),
          MapAnimationOptions(duration: 350),
        );
      } catch (_) {
        // Keep the existing camera if restoration is unavailable.
      }
    }
    if (!mounted || !resumeFollowing || _reportComposerOpen) return;
    setState(() {
      _isFollowing = true;
      _viewport = FollowPuckViewportState(
        zoom: camera?.zoom ?? 14,
        pitch: camera?.pitch ?? 60,
        padding: camera?.padding,
        bearing: FollowPuckViewportStateBearingConstant(
          camera?.bearing ?? _cameraBearing,
        ),
      );
    });
  }

  Future<void> _publishReport(
    ReportCategory category,
    String? description,
  ) async {
    final service = widget.reportService;
    final point = _reportPoint.value;
    if (service == null || point == null) {
      throw StateError('Position du signalement indisponible.');
    }

    final longitude = double.parse(
      point.coordinates.lng.toDouble().toStringAsFixed(6),
    );
    final latitude = double.parse(
      point.coordinates.lat.toDouble().toStringAsFixed(6),
    );
    // Même contenu qu'un envoi raté : on garde le même `client_report_id` pour
    // que le backend ne crée pas de doublon.
    final previous = _pendingReport;
    final request =
        previous != null &&
            previous.matchesContent(
              category: category,
              longitude: longitude,
              latitude: latitude,
              description: description,
            )
        ? previous
        : ManualReportRequest(
            clientReportId: _uuid.v4(),
            category: category,
            longitude: longitude,
            latitude: latitude,
            observedAt: DateTime.now().toUtc(),
            description: description,
          );
    _pendingReport = request;

    await service.createReport(request);
    if (!mounted || !_reportComposerOpen) return;
    unawaited(_closeReportComposer());
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Signalement publié.')));
  }

  void _scheduleReportPointUpdate() {
    if (!_reportComposerOpen || _reportPointTimer?.isActive == true) return;
    _reportPointTimer = Timer(
      const Duration(milliseconds: 60),
      () => unawaited(_updateReportPoint()),
    );
  }

  MbxEdgeInsets _reportCameraPadding() {
    final mapBox = _mapAreaKey.currentContext?.findRenderObject() as RenderBox?;
    final markerBox =
        _reportMarkerKey.currentContext?.findRenderObject() as RenderBox?;
    if (mapBox == null || markerBox == null) {
      return MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0);
    }
    final localCenter = mapBox.globalToLocal(_markerTipGlobal(markerBox));
    final delta = localCenter - mapBox.size.center(Offset.zero);
    return MbxEdgeInsets(
      top: math.max(0, delta.dy * 2),
      left: math.max(0, delta.dx * 2),
      bottom: math.max(0, -delta.dy * 2),
      right: math.max(0, -delta.dx * 2),
    );
  }

  // Convertit la pointe du marqueur (pixels) en coordonnées sur la carte.
  Future<void> _updateReportPoint() async {
    final map = _mapboxMap;
    final mapBox = _mapAreaKey.currentContext?.findRenderObject() as RenderBox?;
    final markerBox =
        _reportMarkerKey.currentContext?.findRenderObject() as RenderBox?;
    if (!_reportComposerOpen ||
        map == null ||
        markerBox == null ||
        mapBox == null) {
      return;
    }
    final mapPixel = mapBox.globalToLocal(_markerTipGlobal(markerBox));
    final request = ++_reportPointRequest;
    try {
      final point = await map.coordinateForPixel(
        ScreenCoordinate(x: mapPixel.dx, y: mapPixel.dy),
      );
      if (!mounted || !_reportComposerOpen || request != _reportPointRequest) {
        return;
      }
      _reportPoint.value = point;
    } catch (_) {
      // Retain the last valid coordinates while the map animates.
    }
  }

  Offset _markerTipGlobal(RenderBox markerBox) => markerBox.localToGlobal(
    Offset(markerBox.size.width / 2, markerBox.size.height - 4),
  );

  ViewportState _viewport = CameraViewportState(
    center: Point(coordinates: Position(-4.49, 48.38)),
    zoom: 7,
    pitch: 60,
  );

  @override
  void dispose() {
    _reportPointTimer?.cancel();
    _reportPoint.dispose();
    final subscription = _positionSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    final headingSubscription = _headingSubscription;
    if (headingSubscription != null) unawaited(headingSubscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardVisible = mediaQuery.viewInsets.bottom > 0;
    if (_reportComposerOpen && _wasKeyboardVisible && !keyboardVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleReportPointUpdate();
      });
    }
    _wasKeyboardVisible = keyboardVisible;
    final reportPanelBottom =
        ReportComposerSheet.heightFor(mediaQuery) +
        mediaQuery.viewInsets.bottom +
        12;
    final gpsLabel = _isLocating
        ? 'Localisation…'
        : _locationError ??
              (_position == null
                  ? 'Position indisponible'
                  : 'Lat. ${formatDms(_position!.latitude, isLatitude: true)}\n'
                        'Lon. ${formatDms(_position!.longitude, isLatitude: false)}');

    return PopScope(
      canPop: !_reportComposerOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _reportComposerOpen) {
          unawaited(_closeReportComposer());
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Positioned.fill(
              child: Listener(
                key: _mapAreaKey,
                onPointerDown: (_) {
                  _mapTouchActive = true;
                  _touchStartBearing = _cameraBearing;
                },
                onPointerUp: (_) => _mapTouchActive = false,
                onPointerCancel: (_) => _mapTouchActive = false,
                child: MapWidget(
                  onMapCreated: (map) {
                    setState(() => _mapboxMap = map);
                    unawaited(MapConfig.hideDefaultOrnaments(map));
                    unawaited(_locate());
                  },
                  onMapLoadedListener: _handleMapLoaded,
                  onMapLoadErrorListener: _handleMapLoadError,
                  onCameraChangeListener: _handleMapCameraChange,
                  onScrollListener: _handleMapGesture,
                  onZoomListener: _handleMapGesture,
                  styleUri: MapConfig.styleUrl,
                  viewport: _viewport,
                ),
              ),
            ),
            if (_mapError != null)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.map_outlined, size: 48),
                          const SizedBox(height: 16),
                          Text(_mapError!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _retryMapLoad,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Réessayer'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (!_reportComposerOpen)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF6F8FA)
                                    .withValues(alpha: 0.90),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                gpsLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF243243),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (widget.onOpenProfile != null) ...[
                          const SizedBox(width: 12),
                          _PoppingMapButton(
                            tooltip: 'Mon profil',
                            onPressed: widget.onOpenProfile,
                            icon: const Icon(
                              Icons.person_outline,
                              color: Color(0xFF243243),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            if (!_reportComposerOpen)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PoppingMapButton(
                          tooltip: 'Créer un signalement',
                          onPressed: _mapError == null
                              ? _openReportComposer
                              : null,
                          icon: const Icon(Icons.add, size: 30),
                        ),
                        if (widget.onOpenCamera != null) ...[
                          const SizedBox(width: 16),
                          _PoppingMapButton(
                            tooltip: 'Signaler avec une photo',
                            onPressed: widget.onOpenCamera,
                            icon: const Icon(
                              Icons.photo_camera_outlined,
                              color: Color(0xFF243243),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            if (!_reportComposerOpen)
              Positioned(
                right: 16,
                bottom: 80,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PoppingMapButton(
                        tooltip: _orientationMode == _MapOrientationMode.north
                            ? 'Aligner la carte sur le cap actuel'
                            : 'Orienter la carte vers le nord',
                        onPressed: _mapboxMap == null || _mapError != null
                            ? null
                            : () => unawaited(_toggleCompass()),
                        icon: _CompassGlyph(headingTurns: _compassTurns),
                      ),
                      const SizedBox(height: 12),
                      _PoppingMapButton(
                        tooltip: 'Recentrer sur ma position',
                        onPressed: _isLocating || _mapboxMap == null
                            ? null
                            : () => unawaited(_locate()),
                        icon: _isLocating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Stack(
                                alignment: Alignment.center,
                                children: [
                                  const Icon(
                                    Icons.my_location,
                                    color: Color(0xFF243243),
                                  ),
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 220),
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: _isFollowing
                                          ? const Color(0xFF329CFF)
                                          : const Color(0xFF243243),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_reportComposerOpen) ...[
              const Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(color: Color(0x220D2238)),
                ),
              ),
              if (!keyboardVisible)
                Positioned(
                  top: mediaQuery.padding.top,
                  bottom: reportPanelBottom,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Transform.translate(
                          offset: const Offset(0, -18),
                          child: SizedBox.square(
                            key: _reportMarkerKey,
                            dimension: 44,
                            child: const Icon(
                              Icons.place,
                              color: Color(0xFF0DB8D5),
                              size: 44,
                              shadows: [
                                Shadow(color: Colors.black87, blurRadius: 8),
                              ],
                            ),
                          ),
                        ),
                        Transform.translate(
                          offset: const Offset(0, 46),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF6F8FA)
                                  .withValues(alpha: 0.94),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              child: ValueListenableBuilder<Point?>(
                                valueListenable: _reportPoint,
                                builder: (context, point, _) => Text(
                                  '${formatDms(point?.coordinates.lat.toDouble() ?? _position!.latitude, isLatitude: true)}\n'
                                  '${formatDms(point?.coordinates.lng.toDouble() ?? _position!.longitude, isLatitude: false)}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFF243243),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                key: const ValueKey('report-composer'),
                left: 0,
                right: 0,
                bottom: 0,
                child: ReportComposerSheet(
                  onClose: () => unawaited(_closeReportComposer()),
                  onPublish: widget.reportService == null
                      ? null
                      : _publishReport,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Icône de la boussole, qui tourne avec le cap du téléphone.
class _CompassGlyph extends StatelessWidget {
  const _CompassGlyph({required this.headingTurns});

  final double headingTurns;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 26,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _CompassRingPainter()),
          ),
          AnimatedRotation(
            turns: headingTurns,
            duration: const Duration(milliseconds: 180),
            child: const Icon(
              Icons.navigation,
              size: 18,
              color: Color(0xFF329CFF),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompassRingPainter extends CustomPainter {
  const _CompassRingPainter();

  @override
  void paint(Canvas canvas, ui.Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.44;
    final ring = Paint()
      ..color = const Color(0xFF243243)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawCircle(center, radius, ring);

    final northMark = Paint()
      ..color = const Color(0xFFFF5757)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2 - 0.20,
      0.40,
      false,
      northMark,
    );
  }

  @override
  bool shouldRepaint(covariant _CompassRingPainter oldDelegate) => false;
}

/// Bouton rond de la carte avec une petite animation au toucher.
class _PoppingMapButton extends StatefulWidget {
  const _PoppingMapButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  State<_PoppingMapButton> createState() => _PoppingMapButtonState();
}

class _PoppingMapButtonState extends State<_PoppingMapButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 210),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.12), weight: 45),
    TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0), weight: 55),
  ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xE6F6F8FA),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          tooltip: widget.tooltip,
          onPressed: widget.onPressed == null
              ? null
              : () {
                  _controller.forward(from: 0);
                  widget.onPressed!();
                },
          icon: IconTheme(
            data: const IconThemeData(color: Color(0xFF243243)),
            child: widget.icon,
          ),
        ),
      ),
    );
  }
}
