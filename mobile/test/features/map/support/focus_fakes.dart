import 'dart:async';
import 'dart:convert';

import 'package:image/image.dart' as img;

import 'package:blueway/core/location/location_service.dart';
import 'package:blueway/features/reports/domain/report_detail.dart';
import 'package:blueway/features/map/presentation/report_marker.dart';
import 'package:blueway/features/reports/domain/manual_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

ReportDetail focusReport({
  String id = 'report-a',
  ReportCategory category = ReportCategory.pollution,
  double longitude = 5.373,
  double latitude = 43.29,
  DateTime? expires,
  ReportPhoto? photo,
}) => ReportDetail(
  id: id,
  category: category,
  description: 'Backend position',
  longitude: longitude,
  latitude: latitude,
  observedAt: DateTime.now(),
  expiresAt: expires ?? DateTime.now().add(const Duration(hours: 1)),
  author: null,
  boat: null,
  photo: photo,
);

geo.Position focusPosition({
  double longitude = 5.37,
  double latitude = 43.29,
  DateTime? timestamp,
  double accuracy = 5,
}) => geo.Position(
  longitude: longitude,
  latitude: latitude,
  timestamp: timestamp ?? DateTime.now(),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: -1,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class FocusGps extends Fake implements LocationService {
  final initial = Completer<geo.Position>();
  final positions = StreamController<geo.Position>.broadcast(sync: true);
  bool allowed = true;
  Future<geo.Position> Function()? onCurrent;
  StateError? permissionError;
  int permissionRequests = 0;
  int currentRequests = 0;
  @override
  Future<void> requestPermission() async {
    permissionRequests++;
    if (permissionError case final error?) throw error;
  }

  @override
  Future<geo.Position> getCurrentPosition() {
    currentRequests++;
    return onCurrent?.call() ?? initial.future;
  }

  @override
  Stream<geo.Position> watchPosition() => positions.stream;
  @override
  Future<bool> canWatchPosition() async => allowed;
  Future<void> close() async {
    if (!initial.isCompleted) initial.complete(focusPosition());
    await positions.close();
  }
}

Future<void> prepareFocusMarkers(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final category in ReportCategory.values) {
      await ReportMarker.paintCategory(category);
    }
  });
}

class FocusStyle extends Fake implements mb.StyleManager {
  final images = <String, mb.MbxImage>{};
  final imageRegistrations = <String>[];
  final layerOrder = <String>[];
  Future<void>? imageGate;

  @override
  Future<void> addStyleImage(
    String id,
    double scale,
    mb.MbxImage image,
    bool sdf,
    List<mb.ImageStretches?> stretchX,
    List<mb.ImageStretches?> stretchY,
    mb.ImageContent? content,
  ) async {
    if (imageGate != null) await imageGate;
    final decoded = img.decodePng(image.data);
    expectSync(decoded, isNotNull);
    expectSync(decoded!.width, image.width);
    expectSync(decoded.height, image.height);
    expectSync(scale, ReportMarker.pixelRatio);
    images[id] = image;
    imageRegistrations.add(id);
  }

  @override
  Future<void> moveStyleLayer(String id, mb.LayerPosition? position) async {
    layerOrder.remove(id);
    layerOrder.add(id);
  }

  @override
  Future<void> removeStyleSource(String id) async {
    sources.remove(id);
  }

  final sources = <String, Map<String, dynamic>>{};
  final layers = <String, Map<String, dynamic>>{};
  bool failSelection = false;
  @override
  Future<bool> styleSourceExists(String id) async => sources.containsKey(id);
  @override
  Future<bool> styleLayerExists(String id) async => layers.containsKey(id);
  @override
  Future<void> addStyleSource(String id, String properties) async {
    if (failSelection && id == 'alert-selected') {
      throw StateError('style unavailable');
    }
    expectSync(sources.containsKey(id), false);
    sources[id] = jsonDecode(properties) as Map<String, dynamic>;
  }

  @override
  Future<void> setStyleSourceProperty(
    String id,
    String property,
    Object value,
  ) async {
    sources[id]![property] = value;
  }

  @override
  Future<void> setStyleSourceProperties(String id, String properties) async {
    sources[id]!.addAll(jsonDecode(properties) as Map<String, dynamic>);
  }

  @override
  Future<void> addStyleLayer(
    String properties,
    mb.LayerPosition? position,
  ) async {
    final layer = jsonDecode(properties) as Map<String, dynamic>;
    expectSync(layers.containsKey(layer['id']), false);
    layers[layer['id'] as String] = layer;
    layerOrder.add(layer['id'] as String);
  }

  @override
  Future<void> setStyleLayerProperty(
    String id,
    String property,
    Object value,
  ) async {
    layers[id]![property] = value;
  }

  @override
  Future<void> removeStyleLayer(String id) async {
    layers.remove(id);
    layerOrder.remove(id);
  }
}

class FocusLocation extends Fake implements mb.LocationSettings {
  final settings = <mb.LocationComponentSettings>[];
  @override
  Future<void> updateSettings(mb.LocationComponentSettings value) async {
    settings.add(value);
  }
}

class _Compass extends Fake implements mb.CompassSettingsInterface {
  @override
  Future<void> updateSettings(mb.CompassSettings settings) async {}
}

class FocusGestures extends Fake implements mb.GesturesSettingsInterface {
  final settings = <mb.GesturesSettings>[];
  @override
  Future<void> updateSettings(mb.GesturesSettings settings) async =>
      this.settings.add(settings);
}

class _Scale extends Fake implements mb.ScaleBarSettingsInterface {
  @override
  Future<void> updateSettings(mb.ScaleBarSettings settings) async {}
}

class FocusMap extends Fake implements mb.MapboxMap {
  @override
  final FocusStyle style = FocusStyle();
  @override
  final FocusLocation location = FocusLocation();
  @override
  final compass = _Compass();
  @override
  final scaleBar = _Scale();
  @override
  final FocusGestures gestures = FocusGestures();
  final interactions = <mb.TypedInteraction>[];
  final fittedCoordinates = <List<mb.Point>>[];
  final fitPadding = <mb.MbxEdgeInsets?>[];
  final cameras = <mb.CameraOptions>[];
  final easedCameras = <mb.CameraOptions>[];
  double nativeZoom = 17;
  double width = 390, height = 844;
  Future<mb.CameraOptions> Function()? onFit;
  Future<mb.Point> Function(mb.ScreenCoordinate)? onCoordinate;
  @override
  void addInteraction<
    T extends mb.TypedFeaturesetFeature<mb.FeaturesetDescriptor>
  >(mb.TypedInteraction<T> interaction, {String? interactionID}) {
    interactions.add(interaction);
  }

  @override
  Future<mb.Size> getSize() async => mb.Size(width: width, height: height);
  @override
  Future<mb.CameraOptions> cameraForCoordinatesPadding(
    List<mb.Point> coordinates,
    mb.CameraOptions camera,
    mb.MbxEdgeInsets? padding,
    double? maxZoom,
    mb.ScreenCoordinate? offset,
  ) async {
    fittedCoordinates.add(coordinates);
    fitPadding.add(padding);
    expectSync(camera.pitch, 0);
    expectSync(camera.bearing, 0);
    expectSync(maxZoom, 20);
    return onFit != null
        ? onFit!()
        : mb.CameraOptions(
            center: coordinates.first,
            zoom: nativeZoom,
            pitch: 0,
            bearing: 0,
          );
  }

  @override
  Future<void> setCamera(mb.CameraOptions camera) async {
    cameras.add(camera);
  }

  @override
  Future<void> easeTo(
    mb.CameraOptions camera,
    mb.MapAnimationOptions? options,
  ) async => easedCameras.add(camera);
  @override
  Future<mb.Point> coordinateForPixel(mb.ScreenCoordinate pixel) async =>
      onCoordinate != null
      ? onCoordinate!(pixel)
      : mb.Point(coordinates: mb.Position(5.37, 43.29));
  @override
  Future<mb.CameraState> getCameraState() async => mb.CameraState(
    center: mb.Point(coordinates: mb.Position(5.37, 43.29)),
    zoom: 14,
    pitch: 0,
    bearing: 0,
    padding: mb.MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
  );
}
