import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/haptics/app_haptics.dart';
import '../../../core/location/coordinate_formatter.dart';
import '../../../core/location/location_service.dart';
import '../../../core/map/location_marker.dart';
import '../../../core/map/cloud_passage_controller.dart';
import '../../../core/map/globe_presentation.dart';
import '../../../core/map/globe_style.dart';
import '../../../core/map/globe_flight.dart';
import '../../../core/map/globe_rotation_controller.dart';
import '../../../core/map/globe_pitch_controller.dart';
import '../../../core/map/map_config.dart';
import '../../../core/map/map_motion.dart';
import '../../../core/map/marine/marine_map_controller.dart';
import '../../../core/sensors/device_orientation_service.dart';
import '../../camera/domain/capture_requirements.dart';
import '../../camera/domain/photo_report_draft.dart';
import '../../reports/data/manual_report_service.dart';
import '../../reports/data/report_detail_service.dart';
import '../../reports/domain/manual_report.dart';
import '../../reports/domain/report_detail.dart';
import '../../reports/domain/report_reach.dart';
import '../../reports/presentation/report_composer_sheet.dart';
import '../../reports/presentation/report_detail_sheet.dart';
import '../data/buoy_layer.dart';
import '../data/fixed_aid_layer.dart';
import '../data/port_layer.dart';
import '../data/harbour_layer.dart';
import '../data/report_layer_controller.dart';
import '../data/report_tiles.dart';
import 'widgets/globe_moon.dart';
import 'widgets/map_edge_zoom.dart';
import 'widgets/globe_stars.dart';
import 'widgets/cloud_passage.dart';
import 'map_alert_camera.dart';
import 'map_focus_controller.dart';
import 'map_intro_controller.dart';
import 'report_marker.dart' as badges;
export 'map_focus_controller.dart';
import 'widgets/map_notice_banner.dart';
import 'widgets/map_scale_bar.dart';
import 'widgets/map_zoom_badge.dart';
import '../data/hydrography_layer.dart';
import 'widgets/report_marker.dart';

/// Le cycle explicite du bouton commence après le premier recentrage.
enum _MapOrientationMode { free, north, heading }

/// Carte principale : position GPS, suivi de l'utilisateur, boussole et
/// création d'un signalement.
///
/// En mode signalement, le marqueur reste fixe à l'écran et c'est la carte
/// qu'on déplace dessous ; le point visé est recalculé à chaque mouvement.
/// Après une photo, le formulaire s'ouvre sur le point estimé, que
/// l'utilisateur confirme ou corrige de la même façon.
class MapScreen extends StatefulWidget {
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenAlerts;
  final MapFocusController? focusController;
  final DeviceOrientationService? orientationService;

  /// Ouvre la caméra ; renvoie null si l'utilisateur la ferme sans photo.
  final Future<PhotoReportDraft?> Function()? onOpenCamera;
  final ManualReportService? reportService;

  /// Couche des signalements publiés ; absente dans les tests.
  final ReportTiles? reportTiles;

  /// Charge la fiche d'un signalement touché sur la carte.
  final ReportDetailService? reportDetailService;
  final VoidCallback? onUserInactive;
  final LocationService? locationService;

  /// Arrivée depuis l'onboarding : la carte se charge sous lui et ne demande
  /// la position qu'à sa fin, puis vole du globe jusqu'à l'utilisateur.
  final MapIntroController? intro;

  const MapScreen({
    super.key,
    this.onOpenProfile,
    this.onOpenAlerts,
    this.focusController,
    this.orientationService,
    this.onOpenCamera,
    this.reportService,
    this.reportTiles,
    this.reportDetailService,
    this.onUserInactive,
    this.locationService,
    this.intro,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  late final _locationService = widget.locationService ?? LocationService();
  StreamSubscription<geo.Position>? _positionSubscription;
  StreamSubscription<double>? _headingSubscription;

  geo.Position? _position;
  double? _deviceHeading;
  double _cameraBearing = 0;
  final _cameraTurns = ValueNotifier<double>(0);
  double _compassTurns = 0;
  bool _isFollowing = false;
  final Set<int> _mapPointers = {};
  final Set<int> _cameraGesturePointers = {};
  bool _cameraPanZoomActive = false;
  bool get _cameraGestureActive =>
      _cameraGesturePointers.isNotEmpty || _cameraPanZoomActive;
  bool _mapPanZoomActive = false;
  bool get _mapTouchActive => _mapPointers.isNotEmpty || _mapPanZoomActive;
  bool _userCameraMotion = false;
  int _mapGestureRevision = 0;
  Timer? _rotationGestureTimer;
  double _touchStartBearing = 0;
  _MapOrientationMode _orientationMode = _MapOrientationMode.free;
  bool _navigationBusy = false;
  int _navigationRevision = 0;
  bool _isLocating = false;
  String? _locationError;
  MapboxMap? _mapboxMap;
  final _marineMap = MarineMapController();
  final _globePresentation = GlobePresentation();
  final _globePitch = GlobePitchController();
  final _globeFlight = GlobeFlight();
  late final _globeRotation = GlobeRotationController(
    moveCamera: (camera) async {
      final map = _mapboxMap;
      if (mounted && !_hidden && map != null) await map.setCamera(camera);
    },
  );
  bool _rotationCameraReady = false;
  int _rotationStyleRevision = 0;

  void _syncGlobeRotation() {
    _globeRotation.configure(
      ready:
          _rotationCameraReady &&
          _styleReady &&
          _mapError == null &&
          !_isFollowing &&
          !_userCameraMotion &&
          !_mapTouchActive &&
          !_reportComposerOpen &&
          !_focusCameraPending &&
          _selectedReport == null,
      visible: !_hidden,
      reduceMotion: _reduceMotion,
    );
  }

  Future<void> _stopGlobeRotation() {
    _rotationGestureTimer?.cancel();
    _userCameraMotion = false;
    return _globeRotation.stopForInteraction();
  }

  void _beginMapGesture({bool newTouch = false}) {
    if (newTouch || !_userCameraMotion) {
      unawaited(_stopGlobeRotation());
      _mapGestureRevision++;
      _userCameraMotion = true;
    }
    _rotationGestureTimer?.cancel();
  }

  void _scheduleRotationAfterGesture() {
    _rotationGestureTimer?.cancel();
    if (!_userCameraMotion || _mapTouchActive) return;
    // Native idle also waits for tiles. Camera silence handles slow networks,
    // while every inertial camera event postpones activation until motion ends.
    _rotationGestureTimer = Timer(
      const Duration(milliseconds: 250),
      _completeMapGesture,
    );
  }

  void _completeMapGesture() {
    if (!mounted || _hidden || _mapTouchActive || !_userCameraMotion) return;
    _rotationGestureTimer?.cancel();
    _userCameraMotion = false;
    _syncGlobeRotation();
    _globeRotation.resumeWhenIdle();
    unawaited(_restoreOrientation());
    unawaited(_keepReportPointInReach());
  }

  /// Zoom du passage dans les nuages, à partir duquel la carte garde
  /// l'orientation laissée par les doigts. En dessous, sur le globe, une
  /// rotation libre ne survit pas au lâcher : le pôle Nord reste en haut.
  static const _freeRotationZoom = 5.0;

  /// Écart maximal, sur le globe, entre les doigts et l'orientation choisie.
  static const _globeRotationLimit = 30.0;

  /// Déplacement à deux doigts réglé dans Mapbox (null : pas encore réglé).
  bool? _pinchPanEnabled;

  /// Rotation des doigts coupée par la butée du globe, rendue au lâcher.
  bool _globeRotationLocked = false;

  /// Sur le globe, deux doigts tournent et zooment sans déplacer la carte :
  /// le déplacement se mêlait à la rotation et la carte glissait de côté.
  void _syncPinchPan(MapboxMap map, double zoom) {
    final enabled = zoom >= _freeRotationZoom;
    if (enabled == _pinchPanEnabled) return;
    _pinchPanEnabled = enabled;
    unawaited(
      MapConfig.updateGestures(map, GesturesSettings(pinchPanEnabled: enabled)),
    );
  }

  /// Réglages natifs des gestes et de l'inertie, puis verrous du globe :
  /// [MapMotion] renvoie tous les gestes, rotation et déplacement à deux
  /// doigts compris.
  Future<void> _configureMotion(MapboxMap map) async {
    await MapMotion.configure(map, reduceMotion: _reduceMotion);
    if (!mounted || map != _mapboxMap) return;
    _pinchPanEnabled = null;
    _globeRotationLocked = false;
    final zoom = _cameraZoom;
    if (zoom != null) _syncPinchPan(map, zoom);
  }

  /// Tous les doigts levés : la rotation coupée à la butée revient.
  void _releaseGlobeRotation() {
    final map = _mapboxMap;
    if (!_globeRotationLocked || _mapTouchActive || map == null) return;
    _globeRotationLocked = false;
    unawaited(
      MapConfig.updateGestures(map, GesturesSettings(rotateEnabled: true)),
    );
  }

  /// Sur le globe, les doigts butent à [_globeRotationLimit] du nord : le
  /// globe ne se retourne pas sous les doigts.
  /// À la butée, la rotation des doigts est coupée jusqu'au lâcher : sinon
  /// Mapbox la recalcule à chaque image, contre le cap posé ici, et la carte
  /// tremble.
  void _limitGlobeRotation(CameraState camera) {
    final map = _mapboxMap;
    if (map == null ||
        !_cameraGestureActive ||
        camera.zoom >= _freeRotationZoom) {
      return;
    }
    final offset = (camera.bearing + 540) % 360 - 180;
    if (offset.abs() <= _globeRotationLimit + .5) return;
    final limit = offset.sign * _globeRotationLimit;
    if (!_globeRotationLocked) {
      _globeRotationLocked = true;
      unawaited(
        MapConfig.updateGestures(map, GesturesSettings(rotateEnabled: false)),
      );
    }
    map.setCamera(CameraOptions(bearing: limit)).ignore();
  }

  /// Au lâcher, sur le globe, la carte revient au nord. Le suivi GPS et
  /// le cap s'arrêtent avant le globe : la carte y est toujours libre.
  Future<void> _restoreOrientation() async {
    final map = _mapboxMap;
    final zoom = _cameraZoom;
    if (map == null ||
        zoom == null ||
        zoom >= _freeRotationZoom ||
        _isFollowing ||
        ((_cameraBearing + 540) % 360 - 180).abs() < 1) {
      return;
    }
    try {
      await _moveCamera(map, CameraOptions(bearing: 0), 300);
    } catch (_) {
      // La prochaine fin de geste retente.
      return;
    }
    // Le retour au nord a coupé la rotation du globe : elle reprend comme
    // après un geste, une fois la caméra immobile.
    if (!mounted || _mapTouchActive) return;
    _userCameraMotion = true;
    _scheduleRotationAfterGesture();
  }

  Future<void> _prepareGlobeRotation() async {
    final revision = ++_rotationStyleRevision;
    _rotationCameraReady = false;
    _syncGlobeRotation();
    final map = _mapboxMap;
    if (map == null) return;
    try {
      final camera = await map.getCameraState();
      if (!mounted || map != _mapboxMap || revision != _rotationStyleRevision) {
        return;
      }
      await _globePitch.synchronize(
        map,
        camera,
        editing: _reportComposerOpen,
        followingPitch: _followingPitch,
      );
      if (!mounted || map != _mapboxMap || revision != _rotationStyleRevision) {
        return;
      }
      _globeRotation.cameraChanged(camera);
      _rotationCameraReady = true;
      _syncGlobeRotation();
    } catch (_) {
      // A later native camera event can establish readiness.
    }
  }

  final _cloudPassage = CloudPassageController();
  final _hydrographyLayer = HydrographyLayer();
  final _buoyLayer = BuoyLayer();
  final _fixedAidLayer = FixedAidLayer();
  String? _mapError;
  bool _reportComposerOpen = false;
  int _reportIntent = 0;
  CameraState? _cameraBeforeReport;
  bool _restoreFollowAfterReport = false;
  final ValueNotifier<Point?> _reportPoint = ValueNotifier(null);
  // Centre du cercle de 1 km : le téléphone à l'ouverture, ou à la photo.
  ({double latitude, double longitude})? _reportOrigin;
  final ValueNotifier<bool> _reportMarkerLifted = ValueNotifier(false);
  Timer? _reportMarkerDropTimer;
  final Uuid _uuid = const Uuid();
  ManualReportRequest? _pendingReport;
  PhotoReportDraft? _photoDraft;

  /// Signalement photo publié dont le JPEG n'est pas encore envoyé.
  String? _publishedReportId;
  bool _isUploadingPhoto = false;
  Timer? _reportPointTimer;
  int _reportPointRequest = 0;
  int _reportMapRevision = 0;
  final _mapAreaKey = GlobalKey();
  final _reportMarkerKey = GlobalKey();
  bool _wasKeyboardVisible = false;
  MapNotice? _notice;
  int _noticeId = 0;
  Timer? _noticeTimer;
  Timer? _selectedExpiryTimer;
  bool _selectedExpired = false;
  ReportDetail? _selectedReport;
  bool _detailOpen = false;
  int _detailRequest = 0;
  double _selectedSheetHeight = 0;
  int _cameraMotionRevision = 0;
  int _focusRevision = -1;
  bool _focusWithUser = false;
  bool _focusCameraPending = false;
  bool _latePositionFocus = false;
  bool _positionFallback = false;
  bool _selectionTouched = false;
  bool _styleReady = false;
  Future<void>? _selectionWork;
  bool _selectionDirty = false;
  int _cameraFocusRevision = 0;

  /// Dernier zoom connu de la caméra.
  double? _cameraZoom;

  /// Zoom visé par le doigt sur un bord, et dernier envoyé à Mapbox : un
  /// seul appel natif à la fois, le suivant part avec le zoom le plus récent.
  double? _edgeZoomTarget;
  double? _edgeZoomSent;
  bool _edgeZoomSending = false;
  final _displayedZoom = ValueNotifier<double>(GlobeStyle.initialZoom);
  final _scaleCamera = ValueNotifier<MapScaleCamera>((
    zoom: GlobeStyle.initialZoom,
    latitude: 0,
  ));

  /// Coupe le renouvellement du token des tuiles et le réseau de Mapbox
  /// quand l'app n'est plus visible.
  AppLifecycleListener? _lifecycleListener;

  /// App en arrière-plan, entre [_pauseMapUpdates] et [_resumeMapUpdates].
  bool _appHidden = false;
  bool _routeHidden = false;
  bool get _hidden => _appHidden || _routeHidden;

  /// Renouvellement périodique du token des tuiles ; arrêté en arrière-plan.
  Timer? _reportTilesTokenTimer;

  /// Installation et état de la couche des signalements (NW-152).
  late final ReportLayerController _reportLayer = ReportLayerController(
    install: _installReportTiles,
    authorize: _authorizeReportTiles,
    connectNetwork: OfflineSwitch.shared.setMapboxStackConnected,
  );

  final _locationMarker = LocationMarker();
  bool _nativeLocationConfigured = false;

  /// Premier affichage complet de la carte, tuiles visibles comprises.
  final _mapLoaded = Completer<void>();
  bool _introStarted = false;

  /// Le vol de l'arrivée n'est pas encore parti ; un doigt sur la carte
  /// l'annule.
  bool _introFlightPending = false;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appHidden = lifecycle != null && lifecycle != AppLifecycleState.resumed;
    widget.intro?.attach();
    widget.intro?.addListener(_handleIntro);
    widget.focusController?.addListener(_handleFocusRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleFocusRequest();
    });
    _lifecycleListener = AppLifecycleListener(
      onInactive: _pauseMapUpdates,
      onHide: _pauseMapUpdates,
      onResume: _resumeMapUpdates,
    );
    _startReportTilesTokenRenewal();
    _reportLayer.status.addListener(_handleReportLayerStatus);
    WidgetsBinding.instance.addObserver(this);
    _headingSubscription =
        (widget.orientationService ?? DeviceOrientationService()).mapHeadings
            .listen(
              (heading) {
                if (!mounted || _hidden) return;
                if (!heading.isFinite) return;
                // Sous l'onboarding, le cap est gardé sans redessiner la
                // carte : iOS n'envoie une nouvelle mesure qu'après 2° de
                // rotation, l'arrivée doit déjà avoir la flèche.
                _deviceHeading = heading;
                if (_covered) return;
                _syncLocationPuck().ignore();
                _setCompassTurnsForHeading(heading);
              },
              onError: (Object _) {
                if (!mounted || _hidden) return;
                _deviceHeading = null;
                _syncLocationPuck().ignore();
                if (_isFollowing &&
                    _orientationMode == _MapOrientationMode.heading) {
                  _showNotice(
                    'Cap du téléphone indisponible.',
                    MapNoticeKind.error,
                  );
                }
              },
            );
  }

  /// En haut de la carte plutôt qu'en SnackBar : le bas est pris par les
  /// boutons.
  void _showNotice(String message, MapNoticeKind kind) {
    _noticeTimer?.cancel();
    setState(() {
      _notice = MapNotice(message, kind);
      _noticeId++;
    });
    _noticeTimer = Timer(const Duration(seconds: 4), _hideNotice);
  }

  void _hideNotice() {
    _noticeTimer?.cancel();
    if (!mounted || _notice == null) return;
    setState(() => _notice = null);
  }

  void _setCompassTurnsForHeading(double heading) {
    final displayedHeading = (_compassTurns * 360) % 360;
    final change = (heading - displayedHeading + 540) % 360 - 180;
    if (change.abs() < 1) return;
    setState(() {
      _compassTurns += change / 360;
      final viewport = _viewport;
      if (_isFollowing &&
          !_mapTouchActive &&
          !_reportComposerOpen &&
          _orientationMode == _MapOrientationMode.heading &&
          viewport is FollowPuckViewportState) {
        _viewport = FollowPuckViewportState(
          zoom: viewport.zoom,
          pitch: viewport.pitch,
          padding: _navigationPadding(heading: true),
          bearing: FollowPuckViewportStateBearingConstant(heading % 360),
        );
      }
    });
  }

  /// Ne change aucun réglage des gestes, de l'inertie ou des déplacements.
  void _stopFollowing() {
    _navigationRevision++;
    _isFollowing = false;
    _orientationMode = _MapOrientationMode.free;
    _viewport = const IdleViewportState();
  }

  double? get _followingPitch {
    final viewport = _viewport;
    return _isFollowing && viewport is FollowPuckViewportState
        ? viewport.pitch
        : null;
  }

  /// Un geste de l'utilisateur coupe le suivi GPS et le cap : la carte
  /// passe en orientation libre.
  void _handleMapCameraChange(CameraChangedEventData event) {
    if (!mounted || _hidden) return;
    final wasRotating = _globeRotation.isRotating;
    final previousZoom = _cameraZoom;
    if (_userCameraMotion) _scheduleRotationAfterGesture();
    final pitchMap = _mapboxMap;
    if (pitchMap != null) {
      _syncPinchPan(pitchMap, event.cameraState.zoom);
      unawaited(
        _globePitch.synchronize(
          pitchMap,
          event.cameraState,
          editing: _reportComposerOpen,
          followingPitch: _followingPitch,
        ),
      );
    }
    _globeRotation.cameraChanged(event.cameraState);
    if (_styleReady) _rotationCameraReady = true;
    _syncGlobeRotation();
    _cameraZoom = event.cameraState.zoom;
    _displayedZoom.value = event.cameraState.zoom;
    _scaleCamera.value = (
      zoom: event.cameraState.zoom,
      latitude: event.cameraState.center.coordinates.lat.toDouble(),
    );
    // Longitude-only rotation leaves zoom-dependent presentation unchanged.
    // Native geographic layers still move; GPS/heading streams update the puck.
    // Avoid rebuilding its image and querying the viewport on each frame.
    if ((wasRotating || _globeRotation.isRotating) &&
        previousZoom == event.cameraState.zoom &&
        GlobeRotationController.allowsZoom(event.cameraState.zoom)) {
      return;
    }
    _reportMapRevision++;
    final map = _mapboxMap;
    if (map != null) _hydrographyLayer.invalidateContourLabels(map);
    _cloudPassage.setCamera(
      zoom: event.cameraState.zoom,
      longitude: event.cameraState.center.coordinates.lng.toDouble(),
      latitude: event.cameraState.center.coordinates.lat.toDouble(),
      bearing: event.cameraState.bearing,
      pitch: event.cameraState.pitch,
    );
    if (map != null) {
      unawaited(_globePresentation.synchronize(map, event.cameraState.zoom));
    }
    _syncLocationPuck().ignore();
    final bearing = event.cameraState.bearing;
    final bearingDelta = ((bearing - _cameraBearing + 540) % 360 - 180);
    final userMovedMap = _cameraGestureActive && _isFollowing;
    final touchBearingDelta =
        ((bearing - _touchStartBearing + 540) % 360 - 180);
    final userRotatedMap = _cameraGestureActive && touchBearingDelta.abs() > 2;
    if (bearingDelta.abs() >= 1) {
      _cameraBearing = bearing;
      _cameraTurns.value += bearingDelta / 360;
    }
    _limitGlobeRotation(event.cameraState);
    if (_reportComposerOpen) {
      _liftReportMarker();
      _scheduleReportPointUpdate();
      return;
    }
    if (!userMovedMap && !userRotatedMap) return;

    setState(_stopFollowing);
  }

  void _handleMapGesture(MapContentGestureContext? _) {
    _beginMapGesture();
    _scheduleRotationAfterGesture();
    if (_reportComposerOpen) return;
    if (!_isFollowing && _viewport is IdleViewportState) return;
    setState(_stopFollowing);
  }

  /// Un doigt posé sur la carte, ou sur ses bords de zoom.
  void _touchMap() {
    _introFlightPending = false;
    // The native report tap can precede this pointer event on iOS.
    if (_selectedReport != null && !_detailOpen) {
      _cameraFocusRevision++;
      _selectionTouched = true;
      _latePositionFocus = false;
      _focusCameraPending = false;
      widget.focusController?.complete(_focusRevision);
    }
    _touchStartBearing = _cameraBearing;
  }

  void _startEdgeZoom() {
    _touchMap();
    _edgeZoomTarget = _cameraZoom;
    _handleMapGesture(null);
  }

  void _edgeZoomBy(double delta) {
    final zoom = _edgeZoomTarget;
    if (zoom == null) return;
    _edgeZoomTarget = (zoom + delta).clamp(0.0, 22.0);
    _beginMapGesture();
    unawaited(_sendEdgeZoom());
  }

  Future<void> _sendEdgeZoom() async {
    if (_edgeZoomSending) return;
    _edgeZoomSending = true;
    try {
      while (mounted && !_hidden) {
        final map = _mapboxMap;
        final zoom = _edgeZoomTarget;
        if (map == null || zoom == null || zoom == _edgeZoomSent) break;
        _edgeZoomSent = zoom;
        await map.setCamera(CameraOptions(zoom: zoom));
      }
    } catch (_) {
      // Zoom refusé par la carte : le prochain mouvement du doigt réessaie.
      _edgeZoomSent = null;
    } finally {
      _edgeZoomSending = false;
    }
  }

  /// Hauteur réservée au « i » de Mapbox sous le logo.
  static const _attributionHeight = 24.0;

  Future<void> _positionMapOrnaments(
    MapboxMap map, {
    required bool editing,
  }) async {
    try {
      final bottom = MediaQuery.viewPaddingOf(context).bottom + 4;
      await Future.wait([
        map.logo.updateSettings(
          LogoSettings(
            position: editing
                ? OrnamentPosition.TOP_LEFT
                : OrnamentPosition.BOTTOM_LEFT,
            marginLeft: 16,
            marginTop: editing ? 64 : 4,
            // En bas, le « i » passe sous le logo, loin du bouton +.
            marginBottom: bottom + _attributionHeight,
          ),
        ),
        // Le « i » obligatoire suit le logo, loin des boutons de droite.
        map.attribution.updateSettings(
          AttributionSettings(
            position: editing
                ? OrnamentPosition.TOP_LEFT
                : OrnamentPosition.BOTTOM_LEFT,
            marginLeft: editing ? 106 : 16,
            marginTop: editing ? 64 : 4,
            marginBottom: bottom,
            iconColor: 0x99FFFFFF,
          ),
        ),
      ]);
    } catch (_) {
      // Ornements non réglables : Mapbox garde sa disposition par défaut.
    }
  }

  bool _navigationIsCurrent(int request) =>
      mounted &&
      !_hidden &&
      !_reportComposerOpen &&
      request == _navigationRevision;

  MbxEdgeInsets _navigationPadding({bool heading = false}) => MbxEdgeInsets(
    // Lower the puck by 12% of the screen to reveal more map ahead of it.
    top: heading ? MediaQuery.sizeOf(context).height * 0.24 : 0,
    left: 0,
    right: 0,
    bottom: 0,
  );

  String get _navigationAction =>
      _isFollowing && _orientationMode == _MapOrientationMode.north
      ? 'Suivre la direction du téléphone'
      : _isFollowing && _orientationMode == _MapOrientationMode.heading
      ? 'Revenir au nord vrai à plat'
      : 'Recentrer sur ma position';

  String get _navigationLabel => switch (_isFollowing
      ? _orientationMode
      : _MapOrientationMode.free) {
    _MapOrientationMode.free => 'Carte libre, nord indiqué',
    _MapOrientationMode.north => 'Centré sur ma position, nord vrai en haut',
    _MapOrientationMode.heading =>
      'Centré sur ma position, direction du téléphone',
  };

  /// Un appui recentre au nord à plat, le suivant suit la direction.
  Future<void> _navigateUser() async {
    final map = _mapboxMap;
    if (map == null || _mapError != null || _navigationBusy || _isLocating) {
      return;
    }
    final followHeading =
        _isFollowing && _orientationMode == _MapOrientationMode.north;
    final request = ++_navigationRevision;
    setState(() => _navigationBusy = true);
    AppHaptics.selection();
    try {
      if (!followHeading) {
        await _locate(animated: true, navigationRequest: request);
        return;
      }
      await _stopGlobeRotation();
      if (!_navigationIsCurrent(request)) return;
      if (_deviceHeading == null) {
        _showNotice('Cap du téléphone indisponible.', MapNoticeKind.error);
        return;
      }
      final bounds = await map.getBounds();
      if (!_navigationIsCurrent(request)) return;
      if (!bounds.maxPitch.isFinite || bounds.maxPitch < 0) {
        throw StateError('Inclinaison indisponible.');
      }
      // The globe temporarily pins the native maximum to zero. A second
      // press during recentering must use the detailed map's actual maximum.
      final maxPitch = bounds.maxPitch == 0
          ? GlobePitchController.maxPitch
          : bounds.maxPitch;
      final viewport = _viewport;
      if (viewport is! FollowPuckViewportState) return;
      final heading = _deviceHeading;
      if (heading == null) {
        _showNotice('Cap du téléphone indisponible.', MapNoticeKind.error);
        return;
      }
      // ignore: experimental_member_use
      _setViewport(
        () {
          _orientationMode = _MapOrientationMode.heading;
          _viewport = FollowPuckViewportState(
            zoom: viewport.zoom,
            padding: _navigationPadding(heading: true),
            pitch: maxPitch * 0.75,
            bearing: FollowPuckViewportStateBearingConstant(heading % 360),
          );
        },
        transition: const DefaultViewportTransition(
          maxDuration: Duration(milliseconds: 350),
        ),
      );
    } catch (_) {
      if (!_navigationIsCurrent(request)) return;
      _showNotice('Impossible de changer l’orientation.', MapNoticeKind.error);
    } finally {
      if (mounted) setState(() => _navigationBusy = false);
    }
  }

  void _handleMapLoadError(MapLoadingErrorEventData event) {
    debugPrint(
      'Chargement Mapbox en échec (${event.type.name}, '
      'source ${event.sourceId ?? '-'}) : ${event.message}',
    );
    if (!mounted) return;

    // La bathymétrie est facultative : son indisponibilité ne doit
    // pas masquer le fond de carte Mapbox.
    if (event.sourceId == MarineMapController.bathymetrySourceId) {
      return;
    }

    // Une panne de la décoration ne masque jamais la carte.
    if (GlobeStyle.isDecorativeSource(event.sourceId)) return;
    if (event.sourceId == GlobeStyle.waterSource) return;
    if (HydrographyLayer.sourceIds.contains(event.sourceId)) return;

    // Les infrastructures portuaires sont un enrichissement facultatif.
    // Leur indisponibilité ne doit jamais masquer le fond Mapbox.
    if (event.sourceId == PortLayer.sourceId ||
        event.sourceId == HarbourLayer.sourceId) {
      return;
    }

    // Une panne du fournisseur de bouées ne masque aucune autre couche.
    if (event.sourceId == BuoyLayer.sourceId) {
      return;
    }

    // Une tuile de signalements en échec ne doit pas cacher le fond de
    // carte, qui reste utilisable.
    if (event.sourceId == ReportTiles.sourceId) {
      // Refus d'accès : le compte est peut-être suspendu, le profil
      // est revalidé. En attendant, la couche passe indisponible comme pour
      // toute autre erreur.
      if (ReportTiles.isForbidden(event.message)) {
        widget.onUserInactive?.call();
      }
      _reportLayer.tileError(event.message, tile: _tileKey(event.tileId));
      return;
    }
    // Réseau coupé en arrière-plan : la carte n'est pas en panne.
    if (_reportLayer.networkCut) return;

    setState(() {
      _mapError = 'Impossible de charger la carte. Vérifiez votre connexion et réessayez.';
    });
    _syncGlobeRotation();
  }

  /// Une tuile des signalements s'est chargée : la couche répond de nouveau.
  void _handleSourceDataLoaded(SourceDataLoadedEventData event) {
    if (event.id != ReportTiles.sourceId) return;
    if (event.type != SourceDataType.TILE) return;
    _reportLayer.tileLoaded(tile: _tileKey(event.tileID));
  }

  static String? _tileKey(TileID? tile) =>
      tile == null ? null : '${tile.z}/${tile.x}/${tile.y}';

  /// Réaffiche le détail de l'alerte à chaque changement d'état.
  void _handleReportLayerStatus() {
    if (mounted) setState(() => _reportLayerNoticeHidden = false);
  }

  bool _reportLayerNoticeHidden = false;

  static const _reportLayerNotice = MapNotice(
    'Signalements indisponibles. Nouvel essai automatique.',
    MapNoticeKind.warning,
  );

  /// Bandeau permanent de la couche, derrière les messages courts.
  MapNotice? get _reportLayerBanner {
    return switch (_reportLayer.status.value) {
      ReportLayerStatus.notInstalled || ReportLayerStatus.unavailable =>
        _reportLayerNoticeHidden
            ? const MapNotice(
                'Signalements indisponibles',
                MapNoticeKind.warning,
              )
            : _reportLayerNotice,
      ReportLayerStatus.pending || ReportLayerStatus.installed => null,
    };
  }

  /// Intervalle entre deux renouvellements du token des tuiles. Firebase
  /// ne donne un nouveau token qu'à moins de 5 min de l'expiration : en
  /// repassant plus souvent, celui de Mapbox n'expire jamais, et les tuiles
  /// redemandées toutes les 15 s ne tombent pas en 401.
  static const _reportTilesTokenInterval = Duration(minutes: 4);

  void _startReportTilesTokenRenewal() {
    _reportTilesTokenTimer?.cancel();
    _reportTilesTokenTimer = Timer.periodic(
      _reportTilesTokenInterval,
      (_) => _reportLayer.renewToken(),
    );
  }

  /// Redonne le token à Mapbox ; le même tant qu'il est encore valide.
  Future<void> _authorizeReportTiles() async {
    final map = _mapboxMap;
    final reportTiles = widget.reportTiles;
    if (!mounted || map == null || reportTiles == null) return;
    await reportTiles.authorize(map);
  }

  /// L'app n'est plus visible : ni renouvellement du token, ni réseau pour
  /// Mapbox.
  void _pauseMapUpdates() {
    if (_appHidden) return;
    _appHidden = true;
    _suspendVisualUpdates();
  }

  void _suspendVisualUpdates() {
    _interruptCameraMotion();
    _syncGlobeRotation();
    _reportTilesTokenTimer?.cancel();
    _reportLayer.pause();
  }

  /// Retour dans l'app : le token a pu expirer entre-temps, on le renouvelle
  /// avant de rebrancher Mapbox, qui redemande alors les tuiles ; la couche
  /// manquante est réinstallée.
  void _resumeMapUpdates() {
    if (!_appHidden) return;
    _appHidden = false;
    if (!_hidden) _restoreVisualUpdates();
  }

  void _restoreVisualUpdates() {
    _syncGlobeRotation();
    _reportLayer.resume();
    _startReportTilesTokenRenewal();
    if (_selectionDirty || _focusCameraPending) unawaited(_applySelection());
    if (_focusWithUser &&
        _selectedReport != null &&
        _positionSubscription == null &&
        !_isLocating) {
      unawaited(
        _locationService
            .canWatchPosition()
            .then((allowed) {
              if (allowed && mounted && !_isLocating) {
                unawaited(_locate(recenter: false));
              }
            })
            .catchError((Object _) {}),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncGlobeRotation();
    final hidden = !TickerMode.valuesOf(context).enabled;
    if (hidden == _routeHidden) return;
    _routeHidden = hidden;
    if (_hidden) {
      _suspendVisualUpdates();
    } else {
      _restoreVisualUpdates();
    }
  }

  void _handleMapLoaded(MapLoadedEventData event) {
    if (!_mapLoaded.isCompleted) _mapLoaded.complete();
    if (!mounted || _mapError == null) return;
    setState(() => _mapError = null);
    _syncGlobeRotation();
  }

  /// Installe l'habillage marin sans bloquer la carte en cas d'échec.
  Future<void> _installMarineMap() async {
    final map = _mapboxMap;
    if (map == null) return;

    try {
      await _marineMap.install(map);
    } catch (error) {
      // La bathymétrie est un enrichissement visuel :
      // son indisponibilité ne doit jamais bloquer la carte NoWave.
      debugPrint('Habillage marin non installé : $error');
    }
  }

  Future<void> _installMarineLayers() async {
    // L'ordre est volontaire :
    //
    // 1. bathymétrie ;
    // 2. courbes / sondes, dangers TOP ; puis infrastructures portuaires ;
    // 3. bouées (slot TOP, sous les reports sans slot) ;
    // 4. aides fixes insérées sous les bouées dans le même slot.
    //
    // La bathymétrie et les docks utilisent le slot BOTTOM.
    // Les ports sont donc ajoutés après ces fonds afin de rester
    // visibles au-dessus de celle-ci.
    await _installMarineMap();

    final map = _mapboxMap;
    if (map == null) return;

    try {
      await _hydrographyLayer.addTo(map);
    } catch (error) {
      debugPrint('Hydrographie non installée : $error');
    }

    try {
      await PortLayer.addTo(map);
    } catch (error) {
      // Comme la bathymétrie, les données portuaires sont facultatives.
      debugPrint('Couche portuaire non installée : $error');
    }

    try {
      await HarbourLayer.addTo(map);
    } catch (e) {
      debugPrint('Ports : installation indisponible : $e');
    }

    try {
      await _buoyLayer.addTo(map);
    } catch (error) {
      debugPrint('Couche bouées non installée : $error');
    }

    try {
      await _fixedAidLayer.addTo(map);
    } catch (error) {
      debugPrint('Aides fixes non installées : $error');
    }
  }

  /// Installe la couche des signalements ; une erreur remonte au
  /// contrôleur, qui retentera sans bloquer la carte.
  Future<void> _installReportTiles() async {
    final map = _mapboxMap;
    final reportTiles = widget.reportTiles;
    if (map == null || reportTiles == null) return;

    await reportTiles.addTo(map);
    debugPrint('Couche des signalements installée.');
    // MVT may arrive after the selection; keep its badge above ordinary points.
    if (_selectedReport != null) unawaited(_applySelection());
  }

  /// Marge autour du doigt pour toucher un badge, en pixels.
  static const _badgeTapRadius = 8.0;

  /// Marge autour du doigt pour toucher une zone : la tache colorée est
  /// bien plus large que son point touchable.
  static const _clusterTapRadius = 32.0;

  /// Niveaux de zoom gagnés en touchant une zone.
  static const _clusterZoomStep = 2.0;

  /// Toucher un badge ouvre sa fiche ; toucher une zone colorée rapproche
  /// la carte. Les interactions restent valables après un changement de
  /// style, qui ne fait que recréer les couches.
  void _addReportInteractions(MapboxMap map) {
    // Selection exists independently from the optional MVT source.
    if (widget.reportDetailService != null) {
      map.addInteraction(
        TapInteraction(
          FeaturesetDescriptor(layerId: 'alert-selected-point'),
          (feature, _) => _openReportDetail(feature),
          radius: _badgeTapRadius,
        ),
      );
    }
    if (widget.reportTiles == null) return;
    map.addInteraction(
      TapInteraction(
        FeaturesetDescriptor(layerId: ReportTiles.pointsLayerId),
        (feature, _) => _openReportDetail(feature),
        radius: _badgeTapRadius,
      ),
    );
    map.addInteraction(
      TapInteraction(
        FeaturesetDescriptor(layerId: ReportTiles.clusterTapLayerId),
        (feature, context) =>
            unawaited(_zoomIntoCluster(feature, context.point)),
        radius: _clusterTapRadius,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.intro != widget.intro) {
      oldWidget.intro?.removeListener(_handleIntro);
      oldWidget.intro?.detach();
      widget.intro?.attach();
      widget.intro?.addListener(_handleIntro);
    }

    if (oldWidget.focusController != widget.focusController) {
      oldWidget.focusController?.removeListener(_handleFocusRequest);
      widget.focusController?.addListener(_handleFocusRequest);
      _focusRevision = -1;
      _handleFocusRequest();
    }
  }

  void _handleFocusRequest() async {
    final controller = widget.focusController;
    if (controller == null || _focusRevision == controller.revision) return;
    _focusRevision = controller.revision;
    final report = controller.report;
    if (report == null && _selectedReport == null && controller.revision == 0) {
      return;
    }
    _interruptCameraMotion();
    _cameraFocusRevision++;
    final revision = _focusRevision;
    await _stopGlobeRotation();
    if (!mounted || revision != _focusRevision) return;
    _selectedExpiryTimer?.cancel();
    setState(() {
      _selectedReport = report;
      _selectedExpired =
          report != null && !report.expiresAt.isAfter(DateTime.now());
      _focusWithUser = controller.includeUserPosition;
      _focusCameraPending = report != null && !_selectedExpired;
      _latePositionFocus = _focusWithUser && !MapAlertCamera.usable(_position);
      _positionFallback = false;
      _selectionTouched = false;
      if (!_reportComposerOpen) {
        _stopFollowing();
      }
    });
    if (report != null) {
      if (_selectedExpired) {
        controller.fail(_focusRevision, const ReportNotFoundException());
      } else {
        _scheduleSelectedExpiry(report);
      }
    }
    unawaited(_applySelection());
  }

  void _scheduleSelectedExpiry(ReportDetail report) {
    _selectedExpiryTimer?.cancel();

    final remaining = report.expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) return;

    _selectedExpiryTimer = Timer(remaining, () {
      if (!mounted || _selectedReport?.id != report.id) return;

      setState(() {
        _selectedExpired = true;
        _positionFallback = false;
      });
      _focusCameraPending = false;
      widget.focusController?.fail(
        _focusRevision,
        const ReportNotFoundException(),
      );
      unawaited(_applySelection());
    });
  }

  Future<void> _applySelection() async {
    _selectionDirty = true;
    final pending = _selectionWork;
    if (pending != null) return pending;
    final work = _drainSelection();
    _selectionWork = work;
    try {
      await work;
    } finally {
      _selectionWork = null;
    }
  }

  bool _isCurrentFocus(int request) {
    if (!mounted || request != _focusRevision) return false;
    if (widget.focusController?.isCurrent(request) ?? true) return true;
    widget.focusController?.clear();
    return false;
  }

  /// Native mutations are serialized; an older fit can never restore a marker
  /// after a more recent selection. A not-yet-created map retains the request.
  Future<void> _drainSelection() async {
    while (mounted &&
        !_hidden &&
        _selectionDirty &&
        _styleReady &&
        !_reportComposerOpen) {
      final map = _mapboxMap;
      if (map == null) return;
      _selectionDirty = false;
      final request = _focusRevision;
      final cameraRequest = _cameraFocusRevision;
      final report = _selectedReport;
      try {
        if (!_isCurrentFocus(request)) continue;
        if (report == null || _selectedExpired) {
          if (await map.style.styleLayerExists('alert-selected-point')) {
            await map.style.removeStyleLayer('alert-selected-point');
          }
          if (await map.style.styleSourceExists('alert-selected')) {
            await map.style.removeStyleSource('alert-selected');
          }
          continue;
        }
        await _showSelectedReport();
        if (!_isCurrentFocus(request)) continue;
        if (_focusCameraPending && !_selectionTouched) {
          final withUser = _focusWithUser;
          final position = _position;
          if (withUser && MapAlertCamera.usable(position)) {
            await _syncLocationPuck();
          }
          if (!mounted) return;
          final currentCamera = await map.getCameraState();
          if (!mounted) return;
          final camera = await MapAlertCamera.fit(
            map,
            report,
            withUser ? position : null,
            MediaQuery.paddingOf(context),
            sheetHeight: withUser ? 0 : _selectedSheetHeight,
            bearing: currentCamera.bearing,
            pitch: currentCamera.pitch,
          );
          if (!_isCurrentFocus(request) ||
              cameraRequest != _cameraFocusRevision ||
              _selectionTouched ||
              _reportComposerOpen) {
            continue;
          }
          setState(() {
            _stopFollowing();
          });
          await WidgetsBinding.instance.endOfFrame;
          if (!_isCurrentFocus(request) ||
              cameraRequest != _cameraFocusRevision ||
              _selectionTouched ||
              _reportComposerOpen) {
            continue;
          }
          await _stopGlobeRotation();
          if (!mounted || cameraRequest != _cameraFocusRevision) continue;
          await _moveCamera(
            map,
            camera,
            MapMotion.focusDurationMs(currentCamera, camera),
          );
          if (!mounted ||
              _hidden ||
              request != _focusRevision ||
              cameraRequest != _cameraFocusRevision) {
            continue;
          }
          _focusCameraPending = false;
          setState(() {
            _positionFallback = withUser && !MapAlertCamera.usable(position);
          });
          if (!_positionFallback) {
            _latePositionFocus = false;
          }
        }
        widget.focusController?.complete(request);
      } catch (error) {
        if (!mounted || request != _focusRevision) continue;
        _focusCameraPending = false;
        _latePositionFocus = false;
        final reported = widget.focusController?.fail(request, error) ?? false;
        if (!reported && _focusWithUser && _isCurrentFocus(request)) {
          // The initial GPS fallback may already have completed. A failure of
          // its one late GPS fit still needs an explicit recovery action.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Impossible de cadrer la carte.'),
              action: SnackBarAction(
                label: 'Réessayer',
                onPressed: () {
                  if (!_isCurrentFocus(request) || _selectedExpired) return;
                  _cameraFocusRevision++;
                  _focusCameraPending = true;
                  _selectionTouched = false;
                  unawaited(_applySelection());
                },
              ),
            ),
          );
        }
      }
    }
  }

  void _positionForSelectedReport() {
    if (!_focusWithUser ||
        _selectedReport == null ||
        !MapAlertCamera.usable(_position)) {
      return;
    }
    if (_positionFallback) setState(() => _positionFallback = false);
    if (!_latePositionFocus || _selectionTouched) return;
    _latePositionFocus = false;
    _cameraFocusRevision++;
    _focusCameraPending = true;
    unawaited(_applySelection());
  }

  /// Repère explicite de la sélection, indépendant du chargement des MVT.
  Future<void> _showSelectedReport() async {
    final report = _selectedReport;
    final map = _mapboxMap;
    if (report == null || map == null || _selectedExpired) return;

    final data = jsonEncode({
      'type': 'Feature',
      'properties': {
        'report_id': report.id,
        'category': report.category.apiValue,
      },
      'geometry': {
        'type': 'Point',
        'coordinates': [report.longitude, report.latitude],
      },
    });

    final imageId = badges.ReportMarker.imageId(report.category);
    final png = await badges.ReportMarker.paintCategory(report.category);
    // Independent of MVT authorization/installation. addStyleImage replaces
    // an existing image, so replaying this after a style reload is safe.
    final side = (badges.ReportMarker.size * badges.ReportMarker.pixelRatio)
        .round();
    await map.style.addStyleImage(
      imageId,
      badges.ReportMarker.pixelRatio,
      MbxImage(width: side, height: side, data: png),
      false,
      [],
      [],
      null,
    );

    if (!await map.style.styleSourceExists('alert-selected')) {
      await map.style.addSource(
        GeoJsonSource(id: 'alert-selected', data: data),
      );
    } else {
      await map.style.setStyleSourceProperty('alert-selected', 'data', data);
    }

    if (!await map.style.styleLayerExists('alert-selected-point') &&
        !_selectedExpired) {
      await map.style.addLayer(
        SymbolLayer(
          id: 'alert-selected-point',
          sourceId: 'alert-selected',
          iconImageExpression: ReportTiles.markerImageExpression(),
          iconSize: 1.15,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          iconEmissiveStrength: 1,
        ),
      );
    }
    await map.style.moveStyleLayer('alert-selected-point', LayerPosition());
  }

  /// Ouvre la fiche du signalement touché, sauf pendant une création.
  void _openReportDetail(FeaturesetFeature feature) {
    final service = widget.reportDetailService;
    final reportId = feature.properties['report_id'];
    if (!mounted || _reportComposerOpen || _detailOpen) return;
    if (service == null || reportId is! String) return;
    _detailOpen = true;
    final detailRequest = ++_detailRequest;
    final focusRevision = _focusRevision;
    ReportDetail? loaded;
    var focused = false;
    AppHaptics.selection();
    final position = _position;
    unawaited(
      ReportDetailSheet.show(
        context,
        reportId: reportId,
        loadReport: (id) async {
          final report = await service.fetchReport(id);
          if (!report.expiresAt.isAfter(DateTime.now())) {
            throw const ReportNotFoundException();
          }
          loaded = report;
          return report;
        },
        loadPhoto: service.fetchPhoto,
        userPosition: position == null
            ? null
            : (latitude: position.latitude, longitude: position.longitude),
        onLayout: (height) {
          final report = loaded;
          if (!mounted ||
              !_detailOpen ||
              detailRequest != _detailRequest ||
              focusRevision != _focusRevision ||
              focused ||
              report == null) {
            return;
          }
          focused = true;
          _selectedSheetHeight = height + 36; // Modal drag handle.
          widget.focusController?.focus(report, origin: MapFocusOrigin.mapTap);
        },
      ).whenComplete(() {
        if (!mounted || detailRequest != _detailRequest) return;
        _detailOpen = false;
        _detailRequest++;
        _selectedSheetHeight = 0;
        if (focused &&
            widget.focusController?.origin == MapFocusOrigin.mapTap &&
            _selectedReport?.id == loaded?.id &&
            !_selectionTouched) {
          unawaited(_clearDetailPadding());
        }
      }),
    );
  }

  /// Closing the sheet does not trigger another flight. Re-express the
  /// current visible camera without padding so the map stays in place.
  Future<void> _clearDetailPadding() async {
    final map = _mapboxMap;
    if (map == null) return;
    _interruptCameraMotion();
    final request = _cameraMotionRevision;
    try {
      final camera = await map.getCameraState();
      final size = await map.getSize();
      final center = await map.coordinateForPixel(
        ScreenCoordinate(x: size.width / 2, y: size.height / 2),
      );
      if (!mounted || _hidden || request != _cameraMotionRevision) return;
      await map.setCamera(
        CameraOptions(
          center: center,
          zoom: camera.zoom,
          bearing: camera.bearing,
          pitch: camera.pitch,
          padding: MbxEdgeInsets(top: 0, left: 0, right: 0, bottom: 0),
        ),
      );
    } catch (_) {
      // A dismissed/replaced native map has no camera left to restore.
    }
  }

  /// Rapproche la carte sur la zone touchée, jusqu'à voir ses badges.
  Future<void> _zoomIntoCluster(FeaturesetFeature feature, Point tapped) async {
    final map = _mapboxMap;
    if (!mounted || map == null || _reportComposerOpen) return;
    AppHaptics.selection();
    final coordinates = feature.geometry['coordinates'];
    final center = coordinates is List && coordinates.length >= 2
        ? Point(
            coordinates: Position(
              (coordinates[0] as num).toDouble(),
              (coordinates[1] as num).toDouble(),
            ),
          )
        : tapped;
    try {
      final zoom = _cameraZoom ?? (await map.getCameraState()).zoom;
      if (!mounted) return;
      // Le suivi GPS reprendrait la caméra pendant l'animation.
      setState(() {
        _stopFollowing();
      });
      await WidgetsBinding.instance.endOfFrame;
      await _moveCamera(
        map,
        CameraOptions(center: center, zoom: zoom + _clusterZoomStep),
        MapMotion.clusterDurationMs,
      );
    } catch (_) {
      // Carte en cours de rechargement : l'utilisateur peut zoomer au doigt.
    }
  }

  /// Réglage d'accessibilité changé pendant que la carte est ouverte.
  @override
  void didChangeAccessibilityFeatures() {
    final map = _mapboxMap;
    if (map != null) unawaited(_configureMotion(map));
    _syncGlobeRotation();
  }

  /// L'utilisateur a demandé moins d'animations : « Supprimer les
  /// animations » sur Android, « Réduire les animations » sur iOS, que
  /// Flutter expose séparément.
  bool get _reduceMotion =>
      (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
      View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;

  void _setViewport(
    VoidCallback change, {
    ViewportTransition? transition = const DefaultViewportTransition(),
  }) {
    // ignore: experimental_member_use
    setStateWithViewportAnimation(
      change,
      transition: _reduceMotion ? null : transition,
    );
  }

  void _interruptCameraMotion() {
    _cameraMotionRevision++;
    _navigationRevision++;
    final map = _mapboxMap;
    if (map != null) {
      unawaited(map.cancelCameraAnimation().catchError((Object _) {}));
    }
  }

  Future<void> _moveCamera(
    MapboxMap map,
    CameraOptions camera,
    int duration,
  ) async {
    final request = ++_cameraMotionRevision;
    await map.cancelCameraAnimation();
    if (!mounted || request != _cameraMotionRevision || _hidden) return;
    await _stopGlobeRotation();
    if (!mounted || request != _cameraMotionRevision || _hidden) return;
    if (_reduceMotion) {
      await map.setCamera(camera);
    } else {
      await map.easeTo(camera, MapAnimationOptions(duration: duration));
    }
  }

  /// Repère NoWave piloté par le même cap que la boussole.
  Future<void> _syncLocationPuck() async {
    final map = _mapboxMap;
    final position = _position;
    if (!mounted || _hidden || map == null || position == null) return;
    if (!_nativeLocationConfigured) {
      _nativeLocationConfigured = true;
      try {
        await map.location.updateSettings(MapConfig.locationPuckSettings());
      } catch (_) {
        _nativeLocationConfigured = false;
        rethrow;
      }
    }
    if (!mounted || _hidden || _mapboxMap != map || !_styleReady) return;
    // Un style en cours de chargement ne doit pas bloquer le recentrage.
    // La prochaine mesure de cap ou de position retente le dessin.
    _locationMarker
        .update(
          map,
          pixelRatio: MediaQuery.devicePixelRatioOf(context),
          latitude: position.latitude,
          longitude: position.longitude,
          heading: _deviceHeading,
        )
        .ignore();
  }

  Future<void> _retryMapLoad() async {
    final map = _mapboxMap;

    if (map == null) return;

    setState(() {
      _mapError = null;
      _styleReady = false;
    });
    _rotationCameraReady = false;
    _rotationStyleRevision++;
    _syncGlobeRotation();

    try {
      await map.loadStyleURI(MapConfig.styleUrl);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _mapError = 'Impossible de charger la carte. Vérifiez votre connexion et réessayez.';
      });
    }
  }

  /// Zoom du recentrage volontaire sur l’utilisateur.
  static const _userZoom = 14.0;
  static const _navigationZoom = 12.0;

  /// Durée maximale du vol vers l'utilisateur au recentrage : Mapbox
  /// raccourcit l'animation quand la distance est faible.
  static const _recenterMaxDuration = Duration(milliseconds: 500);

  /// Vol du globe jusqu'à l'utilisateur à la fin de l'onboarding : première
  /// vue de la carte, assez lent pour suivre la descente.
  static const _introFlightDuration = Duration(milliseconds: 6500);

  /// Attente maximale de la carte avant le fondu, puis de la position avant
  /// de partir vers la France.
  static const _introWait = Duration(seconds: 4);

  /// Sans position : la France entière, juste avant le passage des nuages
  /// ([CloudPassageController.startZoom]).
  static const _franceLongitude = 2.4;
  static const _franceLatitude = 46.6;
  static const _franceZoom = 4.2;

  /// Acquisition indépendante de la caméra, y compris pendant l'accueil.
  void _watchPosition() {
    // Flux partagé avec le suivi des alertes (NW-159), qui peut continuer
    // en arrière-plan : la carte ignore alors les positions.
    _positionSubscription ??= _locationService.watchPosition().listen(
      (position) {
        if (!mounted || _hidden || !MapAlertCamera.usable(position)) return;
        final previous = _position;
        _position = position;
        _positionForSelectedReport();
        _syncLocationPuck().ignore();
        // L'écran ne se redessine que si les coordonnées affichées
        // changent, soit environ tous les 30 m.
        if (_locationError == null &&
            previous != null &&
            _sameDisplayedCoordinates(previous, position)) {
          return;
        }
        setState(() => _locationError = null);
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
  }

  Future<void> _locate({
    bool animated = false,
    bool recenter = true,
    Future<geo.Position>? fix,
    Duration? flight,
    int? navigationRequest,
  }) async {
    final request = navigationRequest ?? _navigationRevision;
    if (recenter) {
      await _stopGlobeRotation();
      if (!mounted) return;
    }
    final gestureRevision = _mapGestureRevision;
    final wasWatching = _positionSubscription != null;
    setState(() {
      _isLocating = true;
      _locationError = null;
    });

    try {
      final position = await (fix ?? _locationService.getCurrentPosition());

      if (!mounted) return;
      if (!MapAlertCamera.usable(position)) {
        throw StateError('Position GPS inexploitable pour le moment.');
      }

      setState(() {
        _position = position;
      });
      _watchPosition();
      _positionForSelectedReport();

      // Curseur remis à chaque recentrage, adapté au zoom actuel.
      _nativeLocationConfigured = false;
      await _syncLocationPuck();

      if (!mounted) return;

      if (!recenter || gestureRevision != _mapGestureRevision) return;
      // A late fix must not undo a gesture, report framing or hidden route.
      if (!_navigationIsCurrent(request)) return;
      if (!animated && _focusWithUser && _selectedReport != null) return;
      if (animated) {
        _cameraFocusRevision++;
        _selectionTouched = true;
        _latePositionFocus = false;
      }
      CameraState? previousCamera;
      if (wasWatching) {
        try {
          previousCamera = await _mapboxMap?.getCameraState();
        } catch (_) {
          // Pas de caméra précédente : valeurs par défaut ci-dessous.
        }
      }

      if (!mounted) return;

      if (!_navigationIsCurrent(request)) return;
      if (gestureRevision != _mapGestureRevision) return;

      void followUser() {
        _isFollowing = true;
        if (animated) _orientationMode = _MapOrientationMode.north;
        _viewport = FollowPuckViewportState(
          zoom: animated ? _navigationZoom : _userZoom,
          padding: animated ? _navigationPadding() : null,
          bearing: const FollowPuckViewportStateBearingConstant(0),
          pitch: animated
              ? 0
              : previousCamera != null &&
                    previousCamera.zoom >= GlobePitchController.detailedZoom
              ? previousCamera.pitch
              : _globePitch.detailedPitch,
        );
      }

      if (flight != null) {
        // L'utilisateur a déjà pris la carte en main : pas de vol.
        if (!_introFlightPending) return;
        _introFlightPending = false;
        unawaited(_flyToUser(position, duration: flight, arrive: followUser));
      } else if (animated) {
        // Mapbox marque cette animation du viewport comme expérimentale.
        // ignore: experimental_member_use
        _setViewport(
          followUser,
          transition: const DefaultViewportTransition(
            maxDuration: _recenterMaxDuration,
          ),
        );
      } else {
        setState(followUser);
      }
    } on StateError catch (error) {
      if (!_navigationIsCurrent(request)) return;
      if (animated) _showNotice(error.message, MapNoticeKind.error);
      setState(() {
        _locationError = error.message;
      });
    } on TimeoutException {
      if (!_navigationIsCurrent(request)) return;
      if (animated) {
        _showNotice(
          'Position introuvable pour le moment. Réessayez.',
          MapNoticeKind.error,
        );
      }
      setState(() {
        _locationError = 'Position introuvable pour le moment. Réessayez.';
      });
    } catch (_) {
      if (!_navigationIsCurrent(request)) return;
      if (animated) {
        _showNotice(
          'Impossible de récupérer votre position.',
          MapNoticeKind.error,
        );
      }
      setState(() {
        _locationError = 'Impossible de récupérer votre position.';
      });
    } finally {
      // A timed-out first fix must not prevent a later stream position from
      // completing the two-point framing. Never ask permission again here.
      if (mounted && _positionSubscription == null) {
        try {
          final allowed = await _locationService.canWatchPosition();
          if (allowed && mounted) _watchPosition();
        } catch (_) {
          // Permission or GPS unavailable: keep the single-report fallback.
        }
      }
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  bool get _covered => widget.intro?.covered ?? false;

  void _handleIntro() {
    final intro = widget.intro;
    if (!mounted || intro == null) return;
    if (intro.phase == MapIntroPhase.starting && !_introStarted) {
      _introStarted = true;
      unawaited(_playIntro(intro));
    }
    final heading = _deviceHeading;
    if (!intro.covered && heading != null) {
      _setCompassTurnsForHeading(heading);
    }
  }

  /// Fin de l'onboarding : l'autorisation de position est demandée tant que
  /// la photo couvre la carte, puis l'onboarding s'efface sur le globe et la
  /// carte vole jusqu'à l'utilisateur.
  Future<void> _playIntro(MapIntroController intro) async {
    Future<geo.Position>? fix;
    String? locationError;
    try {
      await _locationService.requestPermission();
      // La position se cherche pendant l'attente de la carte et le fondu.
      fix = _locationService.getCurrentPosition()..ignore();
    } on StateError catch (error) {
      locationError = error.message;
    } catch (_) {
      locationError = 'Impossible de récupérer votre position.';
    }
    if (!mounted) return;

    try {
      // Chargée pendant l'onboarding, la carte est en général déjà prête.
      await _mapLoaded.future.timeout(_introWait);
    } on TimeoutException {
      // Tuiles encore en chemin : le globe se complète pendant le fondu.
    }
    if (!mounted) return;

    _introFlightPending = true;
    if (_reduceMotion) {
      // Sans animation : la carte s'ouvre déjà sur l'utilisateur, ou sur la
      // France.
      await _arriveFromIntro(fix, locationError);
      if (mounted) intro.reveal();
      return;
    }
    intro.reveal();
    await Future<void>.delayed(MapIntroController.fadeDuration);
    if (!mounted) return;
    await _arriveFromIntro(fix, locationError);
  }

  /// Vol du globe jusqu'à l'utilisateur, tracé ici et non par le viewport
  /// Mapbox : son vol incline la caméra au fil du temps, alors que le globe
  /// la garde à plat ; elle basculait d'un coup après les nuages. Ici,
  /// l'inclinaison suit le zoom ([GlobePitchController.pitchAt]), comme au
  /// doigt. À l'arrivée, le suivi GPS ([arrive]) prend le relais sans saut.
  Future<void> _flyToUser(
    geo.Position position, {
    required Duration duration,
    required VoidCallback arrive,
  }) async {
    final map = _mapboxMap;
    CameraState? start;
    try {
      if (map != null && !_reduceMotion) start = await map.getCameraState();
    } catch (_) {
      // Pas de caméra de départ : arrivée directe.
    }
    if (!mounted) return;
    if (map == null || start == null) return setState(arrive);

    final gestureRevision = _mapGestureRevision;
    setState(() => _viewport = const IdleViewportState());
    final arrived = await _globeFlight.fly(
      path: GlobeFlightPath(
        from: (
          longitude: start.center.coordinates.lng.toDouble(),
          latitude: start.center.coordinates.lat.toDouble(),
          zoom: start.zoom,
          bearing: start.bearing,
        ),
        to: (
          longitude: position.longitude,
          latitude: position.latitude,
          zoom: _userZoom,
          bearing: 0,
        ),
        viewport: MediaQuery.sizeOf(context),
      ),
      duration: duration,
      pitchAt: (zoom) =>
          GlobePitchController.pitchAt(zoom, _globePitch.detailedPitch),
      moveCamera: map.setCamera,
      // Un geste de l'utilisateur lui rend la carte là où elle est.
      interrupted: () =>
          !mounted || _hidden || gestureRevision != _mapGestureRevision,
    );
    if (!mounted || !arrived || gestureRevision != _mapGestureRevision) return;
    setState(arrive);
  }

  /// Vol jusqu'à l'utilisateur. GPS lent ou refusé : la France en attendant,
  /// puis l'utilisateur si sa position arrive avant qu'il touche la carte.
  Future<void> _arriveFromIntro(
    Future<geo.Position>? fix,
    String? locationError,
  ) async {
    if (fix != null) {
      // Le vol part dès que la position arrive, même après ce délai.
      await _locate(
        fix: fix,
        flight: _introFlightDuration,
      ).timeout(_introWait, onTimeout: () {});
    } else {
      setState(() => _locationError = locationError);
    }
    if (!mounted || !_introFlightPending || _isFollowing) return;
    _setViewport(
      () => _viewport = CameraViewportState(
        center: Point(coordinates: Position(_franceLongitude, _franceLatitude)),
        zoom: _franceZoom,
        pitch: 0,
      ),
      transition: const FlyViewportTransition(duration: _introFlightDuration),
    );
  }

  /// Vrai si les deux positions s'affichent pareil, à la seconde d'arc.
  static bool _sameDisplayedCoordinates(geo.Position a, geo.Position b) =>
      formatDms(a.latitude, isLatitude: true) ==
          formatDms(b.latitude, isLatitude: true) &&
      formatDms(a.longitude, isLatitude: false) ==
          formatDms(b.longitude, isLatitude: false);

  Future<void> _openCamera() async {
    await _stopGlobeRotation();
    if (!mounted) return;
    final intent = ++_reportIntent;
    widget.focusController?.setBlocked(true);
    try {
      final draft = await widget.onOpenCamera?.call();
      if (draft == null || !mounted || intent != _reportIntent) return;
      await _waitForCoveringRouteToClose();
      if (!mounted || intent != _reportIntent) return;
      await _openReportComposer(photoDraft: draft, cameraIntent: intent);
    } finally {
      if (mounted && intent == _reportIntent && !_reportComposerOpen) {
        widget.focusController?.setBlocked(false);
      }
    }
  }

  /// Le résultat de la caméra arrive dès le début de sa fermeture : on attend
  /// que la carte soit de nouveau visible pour que l'animation se voie.
  Future<void> _waitForCoveringRouteToClose() async {
    final animation = ModalRoute.of(context)?.secondaryAnimation;
    if (animation == null || animation.isDismissed) return;
    final closed = Completer<void>();
    void listener(AnimationStatus status) {
      if (status != AnimationStatus.dismissed) return;
      animation.removeStatusListener(listener);
      closed.complete();
    }

    animation.addStatusListener(listener);
    await closed.future;
  }

  /// Ouvre le formulaire et mémorise la caméra pour la rétablir à la fermeture.
  /// Avec une photo, le point part de l'estimation plutôt que du GPS actuel.
  Future<void> _openReportComposer({
    PhotoReportDraft? photoDraft,
    int? cameraIntent,
  }) async {
    await _stopGlobeRotation();
    if (!mounted || _reportComposerOpen) return;
    final intent = cameraIntent ?? ++_reportIntent;
    final position = _position;
    final map = _mapboxMap;
    final measurements = photoDraft?.capture.measurements;
    // GPS coupé ou décroché : la carte garde sa dernière position. Le cercle
    // de 1 km ne doit pas se poser là où l'on était, même âge que la photo.
    if (measurements == null &&
        position != null &&
        !isCaptureMeasurementFresh(
          position.timestamp,
          DateTime.now(),
          maxCaptureGpsAge,
        )) {
      _showNotice(
        'Position GPS trop ancienne. Attendez une nouvelle mesure.',
        MapNoticeKind.warning,
      );
      return;
    }
    final origin = measurements != null
        ? (
            latitude: measurements.observerLatitude,
            longitude: measurements.observerLongitude,
          )
        : position == null
        ? null
        : (latitude: position.latitude, longitude: position.longitude);
    // Une estimation au-delà de 1 km se pose sur le bord, dans l'axe de la
    // photo : la direction reste fiable, la distance beaucoup moins.
    final reachable = origin == null
        ? null
        : ReportReach.clamp(
            origin.latitude,
            origin.longitude,
            photoDraft?.initialLatitude ?? origin.latitude,
            photoDraft?.initialLongitude ?? origin.longitude,
          );
    final start = reachable == null
        ? null
        : Position(reachable.longitude, reachable.latitude);
    if (origin == null || start == null || map == null) {
      _showNotice(
        'Attendez que votre position GPS soit disponible.',
        MapNoticeKind.warning,
      );
      return;
    }

    _navigationRevision++;
    widget.focusController?.setBlocked(true);
    CameraState camera;
    try {
      camera = await map.getCameraState();
    } catch (_) {
      if (mounted && intent == _reportIntent) {
        widget.focusController?.setBlocked(false);
      }
      return;
    }
    if (!mounted || intent != _reportIntent) return;

    setState(() {
      _cameraBeforeReport = camera;
      _restoreFollowAfterReport = _isFollowing;
      _reportComposerOpen = true;
      widget.focusController?.setBlocked(true);
      _pendingReport = null;
      _photoDraft = photoDraft;
      _isFollowing = false;
      _reportOrigin = origin;
      _reportPoint.value = Point(coordinates: start);
    });
    unawaited(_showReportReach(map, origin));
    unawaited(_positionMapOrnaments(map, editing: true));
    unawaited(_setMapTiltEnabled(map, false));
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_reportComposerOpen) return;
    final reportPadding = _reportCameraPadding();
    // Caméra déclarée plutôt qu'un easeTo : Mapbox la garde (carte à plat,
    // point sur l'estimation) jusqu'à ce que l'utilisateur touche la carte,
    // sans qu'une fin de suivi GPS puisse l'annuler en cours de route.
    // Mapbox marque cette animation du viewport comme expérimentale.
    // ignore: experimental_member_use
    _setViewport(
      () {
        _viewport = CameraViewportState(
          center: Point(coordinates: start),
          // Plus près en mode photo : l'objet est souvent à quelques
          // dizaines de mètres, et le point doit être ajusté finement.
          zoom: photoDraft == null ? 14 : 16,
          pitch: 0,
          bearing: 0,
          padding: reportPadding,
        );
      },
      transition: const EasingViewportTransition(
        duration: Duration(milliseconds: 350),
      ),
    );
    _scheduleReportPointUpdate();
  }

  Future<void> _closeReportComposer() async {
    if (!_reportComposerOpen) return;
    _reportIntent++;
    FocusManager.instance.primaryFocus?.unfocus();
    _reportPointTimer?.cancel();
    _reportPointRequest++;
    _reportMarkerDropTimer?.cancel();
    _reportMarkerLifted.value = false;
    final camera = _cameraBeforeReport;
    final map = _mapboxMap;
    final resumeFollowing = _restoreFollowAfterReport;
    setState(() {
      _reportComposerOpen = false;
      _reportOrigin = null;
      _reportPoint.value = null;
      _pendingReport = null;
      _photoDraft = null;
      _publishedReportId = null;
      _restoreFollowAfterReport = false;
      // Rend la main à easeTo : la caméra du signalement ne doit plus
      // s'imposer pendant la restauration.
      _viewport = const IdleViewportState();
    });
    if (map != null) {
      unawaited(_positionMapOrnaments(map, editing: false));
      unawaited(_setMapTiltEnabled(map, true));
      unawaited(_hideReportReach(map));
    }
    await WidgetsBinding.instance.endOfFrame;

    if (map != null && camera != null) {
      try {
        await _moveCamera(
          map,
          CameraOptions(
            center: camera.center,
            zoom: camera.zoom,
            pitch: camera.pitch,
            bearing: camera.bearing,
            padding: camera.padding,
          ),
          350,
        );
      } catch (_) {
        // Restauration impossible : la carte reste où elle est.
      }
    }
    if (!mounted || _reportComposerOpen) return;
    if (resumeFollowing) {
      setState(() {
        _isFollowing = true;
        _viewport = FollowPuckViewportState(
          zoom: camera?.zoom ?? _userZoom,
          pitch: camera?.pitch ?? 60,
          padding: switch (_orientationMode) {
            _MapOrientationMode.heading => _navigationPadding(heading: true),
            _MapOrientationMode.north => _navigationPadding(),
            _MapOrientationMode.free => camera?.padding,
          },
          bearing: FollowPuckViewportStateBearingConstant(
            switch (_orientationMode) {
              _MapOrientationMode.north => 0,
              _MapOrientationMode.heading =>
                _deviceHeading ?? camera?.bearing ?? _cameraBearing,
              _MapOrientationMode.free => camera?.bearing ?? _cameraBearing,
            },
          ),
        );
      });
    }
    widget.focusController?.setBlocked(false);
    unawaited(_applySelection());
  }

  Future<void> _publishReport(
    ReportCategory category,
    String? description,
  ) async {
    final service = widget.reportService;
    _reportPointTimer?.cancel();
    final intent = _reportIntent;
    final point = await _updateReportPoint().timeout(
      const Duration(seconds: 5),
      onTimeout: () => null,
    );
    if (!mounted || !_reportComposerOpen || intent != _reportIntent) {
      throw const ReportPositionUnavailable();
    }
    if (service == null || point == null) {
      throw const ReportPositionUnavailable();
    }

    // Publication pendant un glissé au-delà du cercle : le bord fait foi.
    final origin = _reportOrigin;
    final reachable = origin == null
        ? (
            latitude: point.coordinates.lat.toDouble(),
            longitude: point.coordinates.lng.toDouble(),
          )
        : ReportReach.clamp(
            origin.latitude,
            origin.longitude,
            point.coordinates.lat.toDouble(),
            point.coordinates.lng.toDouble(),
          );
    final longitude = double.parse(reachable.longitude.toStringAsFixed(6));
    final latitude = double.parse(reachable.latitude.toStringAsFixed(6));
    final positioning = _photoDraft?.capture.measurements;
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
              positioning: positioning,
            )
        ? previous
        : ManualReportRequest(
            clientReportId: _uuid.v4(),
            category: category,
            longitude: longitude,
            latitude: latitude,
            // En mode photo, l'observation date de la prise de vue.
            observedAt: (positioning?.capturedAt ?? DateTime.now()).toUtc(),
            description: description,
            positioning: positioning,
          );
    _pendingReport = request;

    final reportId = await service.createReport(request);
    if (!mounted || !_reportComposerOpen) return;
    if (_photoDraft != null) {
      // Le formulaire reste ouvert : il enchaîne avec l'envoi de la photo.
      _publishedReportId = reportId;
      return;
    }
    unawaited(_closeReportComposer());
    _showNotice('Signalement publié.', MapNoticeKind.success);
  }

  Future<void> _uploadReportPhoto() async {
    final service = widget.reportService;
    final reportId = _publishedReportId;
    final draft = _photoDraft;
    if (service == null || reportId == null || draft == null) {
      throw StateError('Signalement photo introuvable.');
    }

    _isUploadingPhoto = true;
    try {
      await service.uploadPhoto(
        reportId: reportId,
        jpegBytes: draft.capture.jpegBytes,
      );
    } finally {
      _isUploadingPhoto = false;
    }
    if (!mounted || !_reportComposerOpen) return;
    unawaited(_closeReportComposer());
    _showNotice('Signalement publié avec sa photo.', MapNoticeKind.success);
  }

  /// Le JPEG n'est gardé que pendant ce parcours : fermer après la publication
  /// abandonne la photo, le signalement reste publié.
  void _leaveReportComposer() {
    if (_isUploadingPhoto) return;
    final publishedWithoutPhoto = _publishedReportId != null;
    unawaited(_closeReportComposer());
    if (!publishedWithoutPhoto) return;
    _showNotice('Signalement publié sans photo.', MapNoticeKind.warning);
  }

  /// Sans photo, rien n'indique que le repère est fixe et que c'est la carte
  /// qui bouge dessous.
  String _reportHint() {
    final draft = _photoDraft;
    if (draft == null) return 'Déplacez la carte : 1 km autour de vous au plus';
    final estimate = draft.estimate;
    if (estimate == null) return 'Placez le point sur l’objet photographié';
    final distance = estimate.distanceMeters;
    if (distance > ReportReach.radiusMeters) {
      return 'Estimé au-delà de 1 km · placez le point sur l’objet';
    }
    final distanceText = distance < 1000
        ? '${distance.round()} m'
        : '${(distance / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
    return 'Estimé à $distanceText · ajustez si besoin';
  }

  /// onMapIdle attend aussi le chargement des tuiles, lent en mer : le repère
  /// se pose dès que la caméra ne bouge plus depuis 200 ms.
  void _liftReportMarker() {
    _reportMarkerLifted.value = true;
    _reportMarkerDropTimer?.cancel();
    _reportMarkerDropTimer = Timer(
      const Duration(milliseconds: 200),
      () => _reportMarkerLifted.value = false,
    );
  }

  static const _reportReachSource = 'report-reach';
  static const _reportReachLayer = 'report-reach-outline';

  /// Cercle discret de 1 km autour de l'origine du signalement.
  Future<void> _showReportReach(
    MapboxMap map,
    ({double latitude, double longitude}) origin,
  ) async {
    final data = jsonEncode({
      'type': 'Feature',
      'properties': <String, Object>{},
      'geometry': {
        'type': 'LineString',
        'coordinates': ReportReach.outline(origin.latitude, origin.longitude),
      },
    });
    try {
      if (await map.style.styleSourceExists(_reportReachSource)) {
        await map.style.setStyleSourceProperty(
          _reportReachSource,
          'data',
          data,
        );
      } else {
        await map.style.addSource(
          GeoJsonSource(id: _reportReachSource, data: data),
        );
      }
      if (!await map.style.styleLayerExists(_reportReachLayer)) {
        await map.style.addLayer(
          LineLayer(
            id: _reportReachLayer,
            sourceId: _reportReachSource,
            // Gris foncé : le blanc disparaissait sur la mer claire.
            lineColor: 0xFF4B5563,
            lineOpacity: 0.9,
            lineWidth: 1.5,
            lineDasharray: [2, 2],
            lineEmissiveStrength: 1,
          ),
        );
      }
    } catch (_) {
      // Sans cercle, le retour au bord garde la limite.
    }
  }

  Future<void> _hideReportReach(MapboxMap map) async {
    try {
      if (await map.style.styleLayerExists(_reportReachLayer)) {
        await map.style.removeStyleLayer(_reportReachLayer);
      }
      if (await map.style.styleSourceExists(_reportReachSource)) {
        await map.style.removeStyleSource(_reportReachSource);
      }
    } catch (_) {
      // Style déjà rechargé : le cercle a disparu avec lui.
    }
  }

  /// Au lâcher, un point sorti du cercle revient sur son bord. Pendant le
  /// glissé la carte reste libre : pas de mur sous les doigts.
  Future<void> _keepReportPointInReach() async {
    final map = _mapboxMap;
    final origin = _reportOrigin;
    if (!_reportComposerOpen || map == null || origin == null) return;
    final intent = _reportIntent;
    final point = await _updateReportPoint();
    if (!mounted ||
        point == null ||
        intent != _reportIntent ||
        _mapTouchActive ||
        origin != _reportOrigin) {
      return;
    }
    final latitude = point.coordinates.lat.toDouble();
    final longitude = point.coordinates.lng.toDouble();
    final edge = ReportReach.clamp(
      origin.latitude,
      origin.longitude,
      latitude,
      longitude,
    );
    if (edge.latitude == latitude && edge.longitude == longitude) return;
    try {
      // Le centre de la caméra est la pointe du repère (marge du signalement).
      await _moveCamera(
        map,
        CameraOptions(
          center: Point(coordinates: Position(edge.longitude, edge.latitude)),
        ),
        300,
      );
    } catch (_) {
      // La publication ramène de toute façon le point sur le bord.
    }
  }

  void _scheduleReportPointUpdate() {
    if (!_reportComposerOpen || _reportPointTimer?.isActive == true) return;
    _reportPointTimer = Timer(
      const Duration(milliseconds: 60),
      () => unawaited(_updateReportPoint()),
    );
  }

  /// En signalement, la carte reste à plat : inclinée, elle déformerait les
  /// distances autour du point à placer.
  Future<void> _setMapTiltEnabled(MapboxMap map, bool enabled) async {
    try {
      final camera = await map.getCameraState();
      if (!mounted || map != _mapboxMap) return;
      await _globePitch.synchronize(map, camera, editing: !enabled);
    } catch (_) {
      // The next native camera event also applies the pitch policy.
    }
  }

  EdgeInsets _reportCameraPadding() {
    final mapBox = _mapAreaKey.currentContext?.findRenderObject() as RenderBox?;
    final markerBox =
        _reportMarkerKey.currentContext?.findRenderObject() as RenderBox?;
    if (mapBox == null || markerBox == null) {
      return EdgeInsets.zero;
    }
    final localCenter = mapBox.globalToLocal(_markerTipGlobal(markerBox));
    final delta = localCenter - mapBox.size.center(Offset.zero);
    return EdgeInsets.fromLTRB(
      math.max(0, delta.dx * 2),
      math.max(0, delta.dy * 2),
      math.max(0, -delta.dx * 2),
      math.max(0, -delta.dy * 2),
    );
  }

  /// Convertit la pointe du marqueur (pixels) en coordonnées sur la carte.
  Future<Point?> _updateReportPoint() async {
    final map = _mapboxMap;
    final mapBox = _mapAreaKey.currentContext?.findRenderObject() as RenderBox?;
    final markerBox =
        _reportMarkerKey.currentContext?.findRenderObject() as RenderBox?;
    if (!_reportComposerOpen ||
        map == null ||
        markerBox == null ||
        mapBox == null) {
      return null;
    }
    final mapPixel = mapBox.globalToLocal(_markerTipGlobal(markerBox));
    final request = ++_reportPointRequest;
    final revision = _reportMapRevision;
    final intent = _reportIntent;
    try {
      final point = await map.coordinateForPixel(
        ScreenCoordinate(x: mapPixel.dx, y: mapPixel.dy),
      );
      if (!mounted ||
          !_reportComposerOpen ||
          request != _reportPointRequest ||
          revision != _reportMapRevision ||
          intent != _reportIntent ||
          !point.coordinates.lat.isFinite ||
          !point.coordinates.lng.isFinite ||
          point.coordinates.lat.abs() > 90 ||
          point.coordinates.lng.abs() > 180) {
        return null;
      }
      _reportPoint.value = point;
      return point;
    } catch (_) {
      // Pendant une animation, on garde les dernières coordonnées valides.
      return null;
    }
  }

  Offset _markerTipGlobal(RenderBox markerBox) => markerBox.localToGlobal(
    Offset(
      markerBox.size.width / 2,
      markerBox.size.height - ReportMarker.tipInset,
    ),
  );

  ViewportState _viewport = CameraViewportState(
    center: Point(
      coordinates: Position(
        GlobeStyle.initialLongitude,
        GlobeStyle.initialLatitude,
      ),
    ),
    zoom: GlobeStyle.initialZoom,
    pitch: 0,
  );

  @override
  void dispose() {
    widget.intro?.removeListener(_handleIntro);
    widget.intro?.detach();
    _rotationGestureTimer?.cancel();
    _globeRotation.dispose();
    _globePitch.dispose();
    _globeFlight.dispose();
    widget.focusController?.removeListener(_handleFocusRequest);
    _lifecycleListener?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _reportTilesTokenTimer?.cancel();
    _reportLayer.status.removeListener(_handleReportLayerStatus);
    _reportLayer.dispose();
    _reportPointTimer?.cancel();
    _reportMarkerDropTimer?.cancel();
    _noticeTimer?.cancel();
    _selectedExpiryTimer?.cancel();
    _displayedZoom.dispose();
    _scaleCamera.dispose();
    _cameraTurns.dispose();
    _cloudPassage.dispose();
    _reportPoint.dispose();
    _reportMarkerLifted.dispose();
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
    final shortNotice = _notice;
    final notice =
        shortNotice ??
        (_positionFallback
            ? const MapNotice(
                'Position indisponible — cadrage sur le signalement',
                MapNoticeKind.warning,
              )
            : _reportLayerBanner);
    final gpsLabel = _isLocating
        ? 'Localisation…'
        : _locationError ??
              (_position == null
                  ? 'Position indisponible'
                  : 'Lat. ${formatDms(_position!.latitude, isLatitude: true)}\n'
                        'Lon. ${formatDms(_position!.longitude, isLatitude: false)}');

    // Pendant un signalement, le retour arrière est géré par
    // ReportComposerSheet : il passe par la même confirmation que la croix.
    final screen = Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Both decorations stay behind the transparent native platform view.
          // A retained Flutter background keeps the moon visible while Mapbox
          // continuously redraws; opaque globe surfaces occlude it naturally.
          Positioned.fill(
            child: RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GlobeStars(zoom: _displayedZoom),
                  GlobeMoon(zoom: _displayedZoom),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: Listener(
              key: _mapAreaKey,
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                _cameraGesturePointers.add(event.pointer);
                if (!_detailOpen) _interruptCameraMotion();
                _touchMap();
              },
              onPointerUp: (event) =>
                  _cameraGesturePointers.remove(event.pointer),
              onPointerCancel: (event) =>
                  _cameraGesturePointers.remove(event.pointer),
              onPointerPanZoomStart: (_) => _cameraPanZoomActive = true,
              onPointerPanZoomEnd: (_) => _cameraPanZoomActive = false,
              child: MapWidget(
                // The fixed Flutter stars show through the native space only;
                // globe surfaces and atmospheric fog remain native Mapbox.
                isOpaque: false,
                textureView: true,
                // The default HEIGHT_ONLY constraint locks latitude near
                // the equator at the minimum zoom on tall phone screens.
                mapOptions: MapOptions(
                  constrainMode: ConstrainMode.NONE,
                  pixelRatio: mediaQuery.devicePixelRatio,
                ),
                onMapCreated: (map) {
                  setState(() => _mapboxMap = map);
                  _pinchPanEnabled = null;
                  _globeRotationLocked = false;
                  unawaited(MapConfig.hideDefaultOrnaments(map));
                  unawaited(MapConfig.disableQuickZoom(map));
                  unawaited(_configureMotion(map));
                  unawaited(
                    _positionMapOrnaments(map, editing: _reportComposerOpen),
                  );
                  _addReportInteractions(map);
                  // Sous l'onboarding, la position attend sa fin : pas de
                  // fenêtre d'autorisation par-dessus ses pages.
                  if (!_covered && !_introStarted) unawaited(_locate());
                },
                onMapLoadedListener: _handleMapLoaded,
                onStyleLoadedListener: (_) {
                  _styleReady = true;
                  unawaited(_prepareGlobeRotation());
                  _globePresentation.styleLoaded();
                  _nativeLocationConfigured = false;
                  _syncLocationPuck().ignore();
                  final map = _mapboxMap;
                  if (map != null) {
                    unawaited(_configureMotion(map));
                    unawaited(
                      _globePresentation.synchronize(map, _displayedZoom.value),
                    );
                  }
                  unawaited(_installMarineLayers());
                  unawaited(_applySelection());
                  if (widget.reportTiles != null) _reportLayer.styleLoaded();
                },
                onMapLoadErrorListener: _handleMapLoadError,
                onSourceDataLoadedListener: _handleSourceDataLoaded,
                onCameraChangeListener: _handleMapCameraChange,
                onRenderFrameFinishedListener: (event) {
                  if (!mounted || _hidden || _globeRotation.isRotating) return;
                  // Placement can finish before unrelated network tiles do.
                  if (!event.placementChanged) return;
                  final map = _mapboxMap;
                  if (map != null) {
                    unawaited(_hydrographyLayer.synchronizeContourLabels(map));
                  }
                },
                onMapIdleListener: (_) {
                  _completeMapGesture();
                  if (!mounted || _hidden || _globeRotation.isRotating) return;
                  final map = _mapboxMap;
                  if (map != null) {
                    unawaited(_hydrographyLayer.synchronizeContourLabels(map));
                  }
                },
                onScrollListener: _handleMapGesture,
                onZoomListener: _handleMapGesture,
                styleUri: MapConfig.styleUrl,
                viewport: _viewport,
              ),
            ),
          ),
          Positioned.fill(child: CloudPassage(camera: _cloudPassage)),
          Positioned.fill(
            child: MapEdgeZoom(onStart: _startEdgeZoom, onZoom: _edgeZoomBy),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
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
                                  const SizedBox(height: 4),
                                  MapZoomBadge(zoom: _displayedZoom),
                                ],
                              ),
                            ),
                          ),
                          if (widget.onOpenAlerts != null) ...[
                            const SizedBox(width: 12),
                            _PoppingMapButton(
                              tooltip: 'Mes alertes',
                              onPressed: widget.onOpenAlerts,
                              icon: const Icon(
                                Icons.notifications_outlined,
                                color: Color(0xFF243243),
                              ),
                            ),
                          ],
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
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        // Pas de SizeTransition : son découpage rectangulaire
                        // coupait l'ombre et laissait des coins gris.
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(0, -0.25),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: notice == null
                            ? const SizedBox.shrink()
                            : Padding(
                                key: shortNotice == null
                                    ? const ValueKey('report-layer')
                                    : ValueKey(_noticeId),
                                padding: const EdgeInsets.only(top: 12),
                                child: MapNoticeBanner(
                                  notice: notice,
                                  onDismiss: shortNotice == null
                                      ? () => setState(
                                          () => _reportLayerNoticeHidden = true,
                                        )
                                      : _hideNotice,
                                ),
                              ),
                      ),
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
                          onPressed: _mapError == null
                              ? () => unawaited(_openCamera())
                              : null,
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
              // Sous les boutons de droite, à la hauteur du logo Mapbox.
              bottom: mediaQuery.viewPadding.bottom + 4,
              child: MapScaleBar(camera: _scaleCamera),
            ),
          if (!_reportComposerOpen)
            Positioned(
              right: 16,
              bottom: 260,
              child: SafeArea(
                top: false,
                child: Semantics(
                  label: _navigationLabel,
                  value: _isLocating || _navigationBusy
                      ? 'Localisation…'
                      : null,
                  child: _PoppingMapButton(
                    tooltip: _navigationAction,
                    onPressed:
                        _isLocating ||
                            _navigationBusy ||
                            _mapboxMap == null ||
                            _mapError != null
                        ? null
                        : () => unawaited(_navigateUser()),
                    icon: ValueListenableBuilder<double>(
                      valueListenable: _cameraTurns,
                      builder: (context, cameraTurns, _) => _NavigationGlyph(
                        mode: _isFollowing
                            ? _orientationMode
                            : _MapOrientationMode.free,
                        headingTurns: _compassTurns - cameraTurns,
                        northTurns: -cameraTurns,
                        reduceMotion: _reduceMotion,
                        busy: _isLocating || _navigationBusy,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_reportComposerOpen) ...[
            const Positioned.fill(
              child: IgnorePointer(child: ColoredBox(color: Color(0x220D2238))),
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
                        child: ValueListenableBuilder<bool>(
                          valueListenable: _reportMarkerLifted,
                          builder: (context, lifted, _) => ReportMarker(
                            key: _reportMarkerKey,
                            lifted: lifted,
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
                photo: _photoDraft?.capture.jpegBytes,
                subtitle: _reportHint(),
                onClose: _leaveReportComposer,
                onPublish: widget.reportService == null ? null : _publishReport,
                onUploadPhoto:
                    widget.reportService == null || _photoDraft == null
                    ? null
                    : _uploadReportPhoto,
              ),
            ),
          ],
        ],
      ),
    );
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        _beginMapGesture(newTouch: !_mapTouchActive);
        _mapPointers.add(event.pointer);
      },
      onPointerSignal: (_) {
        _beginMapGesture();
        _scheduleRotationAfterGesture();
      },
      onPointerPanZoomStart: (_) {
        _beginMapGesture(newTouch: true);
        _mapPanZoomActive = true;
      },
      onPointerPanZoomEnd: (_) {
        _mapPanZoomActive = false;
        _releaseGlobeRotation();
        _scheduleRotationAfterGesture();
      },
      onPointerUp: (event) {
        _mapPointers.remove(event.pointer);
        _releaseGlobeRotation();
        _scheduleRotationAfterGesture();
      },
      onPointerCancel: (event) {
        _mapPointers.remove(event.pointer);
        _releaseGlobeRotation();
        _scheduleRotationAfterGesture();
      },
      child: screen,
    );
  }
}

/// Cible, nord vrai ou direction : aucune mention technique sur le bouton.
class _NavigationGlyph extends StatelessWidget {
  const _NavigationGlyph({
    required this.mode,
    required this.headingTurns,
    required this.northTurns,
    required this.reduceMotion,
    required this.busy,
  });

  final _MapOrientationMode mode;
  final double headingTurns;
  final double northTurns;
  final bool reduceMotion;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF329CFF);
    const ink = Color(0xFF243243);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 40,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            AnimatedRotation(
              key: const ValueKey('navigation-compass-rotation'),
              turns: northTurns,
              duration: duration,
              child: SizedBox.square(
                dimension: 40,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    const Positioned.fill(
                      child: CustomPaint(painter: _CompassRingPainter()),
                    ),
                    Positioned(
                      top: -5,
                      // Orbit around the central action, keeping the label
                      // upright and clear of the target/arrow at every angle.
                      child: AnimatedRotation(
                        turns: -northTurns,
                        duration: duration,
                        child: const SizedBox(
                          key: ValueKey('navigation-north-marker'),
                          width: 8,
                          height: 10,
                          child: Center(
                            child: Text(
                              'N',
                              style: TextStyle(
                                fontFamily: 'Raleway',
                                fontSize: 9,
                                height: 1,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFBF5360),
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
            SizedBox.square(
              key: const ValueKey('navigation-center-glyph'),
              dimension: 18,
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(1),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: blue,
                      ),
                    )
                  : mode == _MapOrientationMode.free
                  ? const Icon(Icons.my_location, color: ink, size: 18)
                  : mode == _MapOrientationMode.north
                  ? const Icon(Icons.gps_fixed, size: 18, color: blue)
                  : AnimatedRotation(
                      turns: headingTurns,
                      duration: duration,
                      child: const Icon(
                        Icons.navigation,
                        size: 18,
                        color: blue,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompassRingPainter extends CustomPainter {
  const _CompassRingPainter();

  @override
  void paint(Canvas canvas, ui.Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.37;
    final ring = Paint()
      ..color = const Color(0x708094A8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2 + 0.26,
      2 * math.pi - 0.52,
      false,
      ring,
    );
    for (var index = 1; index < 4; index++) {
      final angle = -math.pi / 2 + index * math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * (radius - 1.8),
        center + direction * radius,
        ring,
      );
    }
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
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: widget.onPressed == null
              ? null
              : () {
                  final reduceMotion =
                      MediaQuery.disableAnimationsOf(context) ||
                      View.of(context)
                          .platformDispatcher
                          .accessibilityFeatures
                          .reduceMotion;
                  if (!reduceMotion) _controller.forward(from: 0);
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
