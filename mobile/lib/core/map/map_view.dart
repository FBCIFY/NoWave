import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';

import 'map_config.dart';
import 'map_controller.dart';

class MapViewOptions {
  const MapViewOptions({
    required this.onReady,
    required this.onCameraMove,
    required this.onError,
    required this.editing,
    required this.generation,
  });
  final void Function(NoWaveMapController) onReady;
  final void Function(CameraPosition) onCameraMove;
  final void Function(String) onError;
  final bool editing;
  final int generation;
}

typedef MapViewBuilder = Widget Function(MapViewOptions options);

/// Vérification du contrat et de la provenance avant de créer le moteur natif.
class NoWaveMapStyle {
  static Future<String> load(http.Client client, String url) async {
    final uri = MapConfig.styleUri(url);
    final response = await client.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (data['version'] != 8 ||
        data['sources'] is! Map ||
        data['layers'] is! List) {
      throw const FormatException('Style MapLibre v8 attendu.');
    }
    final mode = (data['metadata'] as Map?)?['nowave:data_mode'];
    if (!['REGION_REAL', 'CASSIS_REAL', 'DONNEES_FOURNIES'].contains(mode)) {
      throw const FormatException(
        'Un style NoWave avec des données réelles est requis.',
      );
    }
    return jsonEncode(data);
  }
}

/// Charge le JSON en Dart pour rendre les erreurs HTTP visibles sur les deux OS.
/// Le SDK charge ensuite les mêmes MVT, PNG alpha, GeoJSON, sprites et glyphs.
class NoWaveMapView extends StatefulWidget {
  const NoWaveMapView({
    super.key,
    required this.options,
    this.client,
    this.styleUrl = MapConfig.styleUrl,
  });
  final MapViewOptions options;
  final http.Client? client;
  final String styleUrl;
  @override
  State<NoWaveMapView> createState() => _NoWaveMapViewState();
}

class _NoWaveMapViewState extends State<NoWaveMapView> {
  late final _client = widget.client ?? http.Client();
  String? _style;
  MapLibreMapController? _controller;
  Timer? _timeout;
  bool _ready = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load() async {
    try {
      final style = await NoWaveMapStyle.load(_client, widget.styleUrl);
      if (!mounted) return;
      setState(() => _style = style);
      _timeout = Timer(const Duration(seconds: 30), () {
        if (mounted && !_ready) {
          widget.options.onError(
            'La carte ne répond pas. Vérifiez le serveur et réessayez.',
          );
        }
      });
    } catch (error) {
      if (mounted) {
        widget.options.onError('Impossible de charger la carte : $error');
      }
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    if (widget.client == null) _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    if (style == null) return const Center(child: CircularProgressIndicator());
    return MapLibreMap(
      styleString: style,
      // Vue régionale avant le premier GPS, puis zoom 14 sur l'utilisateur.
      initialCameraPosition: const CameraPosition(
        target: LatLng(43.15, 5.35),
        zoom: 7,
        tilt: 60,
      ),
      trackCameraPosition: true,
      compassEnabled: false,
      myLocationEnabled: false,
      tiltGesturesEnabled: !widget.options.editing,
      attributionButtonPosition: widget.options.editing
          ? AttributionButtonPosition.topRight
          : AttributionButtonPosition.bottomRight,
      attributionButtonMargins: widget.options.editing
          ? const math.Point<double>(16, 64)
          : const math.Point<double>(16, 4),
      onMapCreated: (controller) => _controller = controller,
      onCameraMove: widget.options.onCameraMove,
      onStyleLoadedCallback: () {
        if (!mounted || _controller == null) return;
        _timeout?.cancel();
        _ready = true;
        widget.options.onReady(
          MapLibreControllerAdapter(
            _controller!,
            MapProjectionUnits(
              platform: defaultTargetPlatform,
              pixelRatio: MediaQuery.devicePixelRatioOf(context),
            ),
          ),
        );
      },
    );
  }
}
