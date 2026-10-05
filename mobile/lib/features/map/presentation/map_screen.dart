import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:geolocator/geolocator.dart' as geo;
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:precise_compass/precise_compass.dart';
import 'package:uuid/uuid.dart';

import '../../../core/map/accuracy_halo.dart';
import '../../../core/map/map_config.dart';
import '../../../core/location/coordinate_formatter.dart';
import '../../../core/location/location_service.dart';
import '../../../core/sensors/device_orientation_service.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../camera/domain/photo_report_draft.dart';
import '../../reports/presentation/report_composer_sheet.dart';
import '../../reports/presentation/report_detail_sheet.dart';
import '../../reports/data/report_detail_service.dart';
import '../../reports/data/manual_report_service.dart';
import '../../reports/domain/manual_report.dart';
import '../data/report_tiles.dart';
import 'widgets/map_notice_banner.dart';
import 'widgets/report_marker.dart';

/// Nord en haut, carte tournée selon le cap du téléphone, ou rotation libre
/// faite au doigt.
enum _MapOrientationMode { north, heading, manual }

/// Carte principale : position GPS, suivi de l'utilisateur, boussole et
/// création d'un signalement.
///
/// En mode signalement, le marqueur reste fixe à l'écran et c'est la carte
/// qu'on déplace dessous ; le point visé est recalculé à chaque mouvement.
/// Après une photo, le formulaire s'ouvre sur le point estimé, que
/// l'utilisateur confirme ou corrige de la même façon.
class MapScreen extends StatefulWidget {
  final VoidCallback? onOpenProfile;

  /// Ouvre la caméra ; renvoie null si l'utilisateur la ferme sans photo.
  final Future<PhotoReportDraft?> Function()? onOpenCamera;
  final ManualReportService? reportService;

  /// Couche des signalements publiés ; absente dans les tests.
  final ReportTiles? reportTiles;

  /// Charge la fiche d'un signalement touché sur la carte.
  final ReportDetailService? reportDetailService;

  const MapScreen({
    super.key,
    this.onOpenProfile,
    this.onOpenCamera,
    this.reportService,
    this.reportTiles,
    this.reportDetailService,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
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
  final _mapAreaKey = GlobalKey();
  final _reportMarkerKey = GlobalKey();
  bool _wasKeyboardVisible = false;
  MapNotice? _notice;
  int _noticeId = 0;
  Timer? _noticeTimer;

  /// Dernier zoom connu, pour relancer le battement de la heatmap au
  /// retour au premier plan.
  double? _cameraZoom;

  /// Coupe le battement de la heatmap et le renouvellement du token des
  /// tuiles quand l'app n'est plus visible.
  AppLifecycleListener? _lifecycleListener;

  /// Renouvellement périodique du token des tuiles ; arrêté en arrière-plan.
  Timer? _reportTilesTokenTimer;

  /// Halo de précision du GPS, sous le curseur et sous les signalements :
  /// un danger reste lisible même quand la position est approximative.
  final _accuracyHalo = AccuracyHalo(below: ReportTiles.heatmapLayerId);

  /// Curseur affiché : point bleu de loin (true), flèche 3D de près (false),
  /// null avant la première position.
  bool? _puckZoomedOut;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onHide: _pauseMapUpdates,
      onShow: _resumeMapUpdates,
    );
    _startReportTilesTokenRenewal();
    WidgetsBinding.instance.addObserver(this);
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
    setState(() => _compassTurns += change / 360);
  }

  /// Un geste de l'utilisateur coupe le suivi GPS ; une rotation au doigt
  /// passe la boussole en mode manuel.
  void _handleMapCameraChange(CameraChangedEventData event) {
    _cameraZoom = event.cameraState.zoom;
    _syncHeatmapPulse();
    _syncLocationPuck().ignore();
    final bearing = event.cameraState.bearing;
    final bearingDelta = ((bearing - _cameraBearing + 540) % 360 - 180);
    final userMovedMap = _mapTouchActive && _isFollowing;
    final touchBearingDelta =
        ((bearing - _touchStartBearing + 540) % 360 - 180);
    final userRotatedMap = _mapTouchActive && touchBearingDelta.abs() > 2;
    if (bearingDelta.abs() >= 1) _cameraBearing = bearing;
    if (_reportComposerOpen) {
      _liftReportMarker();
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
      // Ornements non réglables : Mapbox garde sa disposition par défaut.
    }
  }

  /// Bascule entre nord en haut et cap du téléphone.
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
      _showNotice('Cap du téléphone indisponible.', MapNoticeKind.error);
      return;
    }
    AppHaptics.selection();
    final targetBearing = nextMode == _MapOrientationMode.north
        ? 0.0
        : heading!;

    try {
      if (_isFollowing) {
        final camera = await map.getCameraState();
        if (!mounted) return;
        // Mapbox marque cette animation du viewport comme expérimentale.
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
      _showNotice('Impossible de changer l’orientation.', MapNoticeKind.error);
    }
  }

  /// Dernière relance de la couche des signalements après une tuile en
  /// échec : en déplaçant la carte, les erreurs arrivent par dizaines.
  DateTime? _lastReportTilesRetry;

  /// Intervalle minimal entre deux relances de la couche des signalements.
  static const _reportTilesRetryInterval = Duration(seconds: 30);

  void _handleMapLoadError(MapLoadingErrorEventData event) {
    debugPrint(
      'Chargement Mapbox en échec (${event.type.name}, '
      'source ${event.sourceId ?? '-'}) : ${event.message}',
    );
    if (!mounted) return;

    // Une tuile de signalements en échec ne doit pas cacher le fond de
    // carte, qui reste utilisable.
    if (event.sourceId == ReportTiles.sourceId) {
      _handleReportTilesError();
      return;
    }

    setState(() {
      _mapError = 'Impossible de charger la carte. Vérifiez votre connexion et réessayez.';
    });
  }

  /// Le token Firebase expire au bout d'une heure : on le redonne à Mapbox,
  /// qui l'enverra avec les prochaines tuiles, et on prévient sans bloquer.
  void _handleReportTilesError() {
    final map = _mapboxMap;
    final reportTiles = widget.reportTiles;
    final now = DateTime.now();
    final lastRetry = _lastReportTilesRetry;
    if (map == null || reportTiles == null) return;
    if (lastRetry != null &&
        now.difference(lastRetry) < _reportTilesRetryInterval) {
      return;
    }
    _lastReportTilesRetry = now;
    unawaited(
      reportTiles.authorize(map).catchError((Object error) {
        debugPrint('Token des signalements non renouvelé : $error');
      }),
    );
    _showNotice(
      'Signalements momentanément indisponibles.',
      MapNoticeKind.warning,
    );
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
      (_) => _renewReportTilesToken(),
    );
  }

  /// Redonne le token à Mapbox ; le même tant qu'il est encore valide.
  void _renewReportTilesToken() {
    final map = _mapboxMap;
    final reportTiles = widget.reportTiles;
    if (!mounted || map == null || reportTiles == null) return;
    unawaited(
      reportTiles.authorize(map).catchError((Object error) {
        debugPrint('Token des signalements non renouvelé : $error');
      }),
    );
  }

  /// L'app n'est plus visible : ni battement ni renouvellement du token.
  void _pauseMapUpdates() {
    widget.reportTiles?.stopPulse();
    _reportTilesTokenTimer?.cancel();
  }

  /// Retour dans l'app : le token a pu expirer entre-temps, on le renouvelle
  /// avant que Mapbox ne redemande les tuiles.
  void _resumeMapUpdates() {
    _syncHeatmapPulse();
    _renewReportTilesToken();
    _startReportTilesTokenRenewal();
  }

  void _handleMapLoaded(MapLoadedEventData event) {
    if (!mounted || _mapError == null) return;
    setState(() => _mapError = null);
  }

  /// Chaque chargement de style efface les couches ajoutées : on remet celle
  /// des signalements. Une erreur ici ne doit pas bloquer la carte.
  Future<void> _addReportTiles() async {
    final map = _mapboxMap;
    final reportTiles = widget.reportTiles;
    if (map == null || reportTiles == null) return;

    try {
      await reportTiles.addTo(map);
      _cameraZoom ??= (await map.getCameraState()).zoom;
      _syncHeatmapPulse();
    } catch (error) {
      debugPrint('Couche des signalements indisponible : $error');
    }
  }

  /// Marge autour du doigt pour toucher un badge, en pixels.
  static const _badgeTapRadius = 8.0;

  /// Marge autour du doigt pour toucher le nombre d'une zone : la zone
  /// colorée est bien plus large que le nombre.
  static const _clusterTapRadius = 32.0;

  /// Niveaux de zoom gagnés en touchant une zone.
  static const _clusterZoomStep = 2.0;

  /// Toucher un badge ouvre sa fiche ; toucher le nombre d'une zone
  /// rapproche la carte. Les interactions restent valables après un
  /// changement de style, qui ne fait que recréer les couches.
  void _addReportInteractions(MapboxMap map) {
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
        FeaturesetDescriptor(layerId: ReportTiles.countLayerId),
        (feature, context) =>
            unawaited(_zoomIntoCluster(feature, context.point)),
        radius: _clusterTapRadius,
      ),
    );
  }

  /// Ouvre la fiche du signalement touché, sauf pendant une création.
  void _openReportDetail(FeaturesetFeature feature) {
    final service = widget.reportDetailService;
    final reportId = feature.properties['report_id'];
    if (!mounted || _reportComposerOpen) return;
    if (service == null || reportId is! String) return;
    AppHaptics.selection();
    final position = _position;
    unawaited(
      ReportDetailSheet.show(
        context,
        reportId: reportId,
        loadReport: service.fetchReport,
        userPosition: position == null
            ? null
            : (latitude: position.latitude, longitude: position.longitude),
      ),
    );
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
        _isFollowing = false;
        _viewport = const IdleViewportState();
      });
      await WidgetsBinding.instance.endOfFrame;
      await map.easeTo(
        CameraOptions(center: center, zoom: zoom + _clusterZoomStep),
        MapAnimationOptions(duration: 500),
      );
    } catch (_) {
      // Carte en cours de rechargement : l'utilisateur peut zoomer au doigt.
    }
  }

  /// Réglage d'accessibilité changé pendant que la carte est ouverte.
  @override
  void didChangeAccessibilityFeatures() => _syncHeatmapPulse();

  /// L'utilisateur a demandé moins d'animations : « Supprimer les
  /// animations » sur Android, « Réduire les animations » sur iOS, que
  /// Flutter expose séparément.
  bool get _reduceMotion =>
      (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
      View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;

  /// La heatmap bat tant qu'elle est visible, sauf si l'utilisateur a
  /// demandé moins d'animations dans les réglages du téléphone.
  void _syncHeatmapPulse() {
    final map = _mapboxMap;
    final zoom = _cameraZoom;
    if (!mounted || map == null || zoom == null) return;
    widget.reportTiles?.updatePulse(map, zoom: zoom, enabled: !_reduceMotion);
  }

  /// Point bleu de loin, flèche 3D de près. Mapbox ne change de curseur
  /// que quand le zoom franchit le seuil.
  Future<void> _syncLocationPuck() async {
    final map = _mapboxMap;
    if (map == null || _position == null) return;
    final zoomedOut =
        (_cameraZoom ?? _userZoom) < MapConfig.detailedPuckMinZoom;
    if (zoomedOut == _puckZoomedOut) return;
    _puckZoomedOut = zoomedOut;
    try {
      await map.location.updateSettings(
        MapConfig.locationPuckSettings(zoomedOut: zoomedOut),
      );
    } catch (_) {
      // Réessayé au prochain mouvement de la caméra.
      _puckZoomedOut = null;
      rethrow;
    }
  }

  /// Place le halo de précision sur [position], ou sur la dernière position
  /// connue après un chargement de style.
  void _showAccuracyHalo([geo.Position? position]) {
    final map = _mapboxMap;
    final at = position ?? _position;
    if (map == null || at == null) return;
    unawaited(
      _accuracyHalo.show(
        map,
        latitude: at.latitude,
        longitude: at.longitude,
        accuracy: at.accuracy,
      ),
    );
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

  /// Zoom sur l'utilisateur au lancement et à chaque recentrage.
  static const _userZoom = 14.0;

  /// Durée maximale du vol vers l'utilisateur au recentrage : Mapbox
  /// raccourcit l'animation quand la distance est faible.
  static const _recenterMaxDuration = Duration(milliseconds: 1200);

  /// Centre la carte sur l'utilisateur puis le suit à chaque nouvelle position.
  /// [animated] : vol jusqu'à l'utilisateur (bouton), sinon saut direct
  /// (lancement de la carte).
  Future<void> _locate({bool animated = false}) async {
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
      _showAccuracyHalo(position);

      // Curseur remis à chaque recentrage, adapté au zoom actuel.
      _puckZoomedOut = null;
      await _syncLocationPuck();

      if (!mounted) return;

      CameraState? previousCamera;
      if (_positionSubscription != null) {
        try {
          previousCamera = await _mapboxMap?.getCameraState();
        } catch (_) {
          // Pas de caméra précédente : valeurs par défaut ci-dessous.
        }
      }

      if (!mounted) return;

      void followUser() {
        _isFollowing = true;
        _viewport = FollowPuckViewportState(
          // Toujours le zoom du lancement : après un dézoom sur le globe,
          // recentrer doit aussi ramener au niveau de la rue.
          zoom: _userZoom,
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
      }

      if (animated) {
        // Mapbox marque cette animation du viewport comme expérimentale.
        // ignore: experimental_member_use
        setStateWithViewportAnimation(
          followUser,
          transition: const DefaultViewportTransition(
            maxDuration: _recenterMaxDuration,
          ),
        );
      } else {
        setState(followUser);
      }

      _positionSubscription ??=
          geo.Geolocator.getPositionStream(
            locationSettings: const geo.LocationSettings(
              accuracy: geo.LocationAccuracy.high,
              // Chaque position, même immobile : le halo doit rétrécir
              // quand la précision s'améliore.
              distanceFilter: 0,
            ),
          ).listen(
            (position) {
              if (!mounted) return;
              _showAccuracyHalo(position);
              final previous = _position;
              _position = position;
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

  /// Vrai si les deux positions s'affichent pareil, à la seconde d'arc.
  static bool _sameDisplayedCoordinates(geo.Position a, geo.Position b) =>
      formatDms(a.latitude, isLatitude: true) ==
          formatDms(b.latitude, isLatitude: true) &&
      formatDms(a.longitude, isLatitude: false) ==
          formatDms(b.longitude, isLatitude: false);

  Future<void> _openCamera() async {
    final draft = await widget.onOpenCamera?.call();
    if (draft == null || !mounted) return;
    await _waitForCoveringRouteToClose();
    if (!mounted) return;
    await _openReportComposer(photoDraft: draft);
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
  Future<void> _openReportComposer({PhotoReportDraft? photoDraft}) async {
    if (_reportComposerOpen) return;
    final position = _position;
    final map = _mapboxMap;
    final start = photoDraft != null
        ? Position(photoDraft.initialLongitude, photoDraft.initialLatitude)
        : position == null
        ? null
        : Position(position.longitude, position.latitude);
    if (start == null || map == null) {
      _showNotice(
        'Attendez que votre position GPS soit disponible.',
        MapNoticeKind.warning,
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
      _photoDraft = photoDraft;
      _isFollowing = false;
      _reportPoint.value = Point(coordinates: start);
    });
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
    setStateWithViewportAnimation(
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
    }
    await WidgetsBinding.instance.endOfFrame;

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
        // Restauration impossible : la carte reste où elle est.
      }
    }
    if (!mounted || !resumeFollowing || _reportComposerOpen) return;
    setState(() {
      _isFollowing = true;
      _viewport = FollowPuckViewportState(
        zoom: camera?.zoom ?? _userZoom,
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
    if (draft == null) return 'Déplacez la carte pour placer le point';
    final estimate = draft.estimate;
    if (estimate == null) return 'Placez le point sur l’objet photographié';
    final distance = estimate.distanceMeters;
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
      await map.gestures.updateSettings(
        GesturesSettings(pitchEnabled: enabled),
      );
    } catch (_) {
      // Réglages des gestes indisponibles : l'inclinaison reste possible.
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
      // Pendant une animation, on garde les dernières coordonnées valides.
    }
  }

  Offset _markerTipGlobal(RenderBox markerBox) => markerBox.localToGlobal(
    Offset(
      markerBox.size.width / 2,
      markerBox.size.height - ReportMarker.tipInset,
    ),
  );

  ViewportState _viewport = CameraViewportState(
    center: Point(coordinates: Position(-4.49, 48.38)),
    zoom: 7,
    pitch: 60,
  );

  @override
  void dispose() {
    widget.reportTiles?.stopPulse();
    _lifecycleListener?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _reportTilesTokenTimer?.cancel();
    _reportPointTimer?.cancel();
    _reportMarkerDropTimer?.cancel();
    _noticeTimer?.cancel();
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
    final notice = _notice;
    final gpsLabel = _isLocating
        ? 'Localisation…'
        : _locationError ??
              (_position == null
                  ? 'Position indisponible'
                  : 'Lat. ${formatDms(_position!.latitude, isLatitude: true)}\n'
                        'Lon. ${formatDms(_position!.longitude, isLatitude: false)}');

    // Pendant un signalement, le retour arrière est géré par
    // ReportComposerSheet : il passe par la même confirmation que la croix.
    return Scaffold(
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
                  _addReportInteractions(map);
                  unawaited(_locate());
                },
                onMapLoadedListener: _handleMapLoaded,
                onStyleLoadedListener: (_) {
                  _showAccuracyHalo();
                  unawaited(_addReportTiles());
                },
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
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
                                key: ValueKey(_noticeId),
                                padding: const EdgeInsets.only(top: 12),
                                child: MapNoticeBanner(
                                  notice: notice,
                                  onDismiss: _hideNotice,
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
                          : () {
                              AppHaptics.selection();
                              unawaited(_locate(animated: true));
                            },
                      icon: _isLocating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
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
