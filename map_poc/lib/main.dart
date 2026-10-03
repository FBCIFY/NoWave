import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';

import 'map_style.dart';

const styleUrl = String.fromEnvironment(
  'NOWAVE_STYLE_URL',
  defaultValue: 'http://127.0.0.1:8765/style.json',
);

void main() {
  MapLibreMap.webLibrarySource = const MapLibreJsSource.urls(
    scriptUrl: 'vendor/maplibre/maplibre-gl.mjs',
    styleUrl: 'vendor/maplibre/maplibre-gl.css',
  );
  runApp(const NoWaveMapPoc());
}

class NoWaveMapPoc extends StatelessWidget {
  const NoWaveMapPoc({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NoWave · Carte jour',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF337FAF)),
      scaffoldBackgroundColor: const Color(0xFFF4FBFF),
      useMaterial3: true,
    ),
    home: const MapPocScreen(),
  );
}

class MapPocScreen extends StatefulWidget {
  const MapPocScreen({super.key, this.client});
  final http.Client? client;

  @override
  State<MapPocScreen> createState() => _MapPocScreenState();
}

class _MapPocScreenState extends State<MapPocScreen> {
  late final http.Client _client = widget.client ?? http.Client();
  MapStyle? _style;
  MapLibreMapController? _map;
  Timer? _loadTimer;
  String? _error;
  bool _ready = false;
  double _zoom = 10.5;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _loadTimer?.cancel();
    setState(() {
      _style = null;
      _error = null;
      _ready = false;
      _map = null;
    });
    try {
      final style = await MapStyle.load(_client, Uri.parse(styleUrl));
      if (!mounted || generation != _generation) return;
      setState(() {
        _style = style;
        _zoom = style.zoom;
      });
      _loadTimer = Timer(const Duration(seconds: 30), () {
        if (mounted && !_ready) {
          setState(
            () => _error =
                'La carte ne répond pas. Vérifier le serveur et les assets.',
          );
        }
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Chargement impossible : $error');
      }
    }
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    if (widget.client == null) _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    return Scaffold(
      appBar: AppBar(
        title: const Text('NoWave'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text('JOUR  ·  z ${_zoom.toStringAsFixed(1)}'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (style != null)
            Container(
              width: double.infinity,
              color: style.isDemo
                  ? const Color(0xFFFFF1C9)
                  : const Color(0xFFDCEFFA),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                style.isDemo
                    ? 'DÉMO FICTIVE — île, profondeurs et objets inventés.\nTest visuel uniquement.'
                    : 'Données fournies — couverture et fiabilité à vérifier auprès des sources.',
                style: const TextStyle(fontSize: 12, color: Color(0xFF20262C)),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                if (style != null && _error == null)
                  MapLibreMap(
                    key: ValueKey(_generation),
                    styleString: style.json,
                    initialCameraPosition: CameraPosition(
                      target: LatLng(style.latitude, style.longitude),
                      zoom: style.zoom,
                    ),
                    minMaxZoomPreference: const MinMaxZoomPreference(4, 18),
                    myLocationEnabled: false,
                    compassEnabled: false,
                    tiltGesturesEnabled: false,
                    rotateGesturesEnabled: false,
                    trackCameraPosition: true,
                    onMapCreated: (controller) => _map = controller,
                    onStyleLoadedCallback: () {
                      _loadTimer?.cancel();
                      if (mounted) setState(() => _ready = true);
                    },
                    onCameraIdle: () {
                      final zoom = _map?.cameraPosition?.zoom;
                      if (mounted && zoom != null) setState(() => _zoom = zoom);
                    },
                  ),
                if (_error != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off, size: 32),
                          const SizedBox(height: 16),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Réessayer'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (!_ready)
                  const Center(child: CircularProgressIndicator()),
                if (_ready && _error == null)
                  const Positioned(
                    left: 12,
                    right: 12,
                    bottom: 28,
                    child: IgnorePointer(child: _DepthLegend()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DepthLegend extends StatelessWidget {
  const _DepthLegend();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xEEF4FBFF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Profondeur · mètres', style: TextStyle(fontSize: 11)),
          const SizedBox(height: 6),
          Container(
            height: 7,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(4)),
              gradient: LinearGradient(
                colors: [
                  Color(0xFFF4FBFF),
                  Color(0xFFDCEFFA),
                  Color(0xFFB9DFF2),
                  Color(0xFF8FCBE7),
                  Color(0xFF5AA9D0),
                  Color(0xFF337FAF),
                  Color(0xFF1E5D8A),
                  Color(0xFF123F67),
                  Color(0xFF0C2F50),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0–2'),
              Text('10'),
              Text('50'),
              Text('200'),
              Text('1000+'),
            ],
          ),
        ],
      ),
    ),
  );
}
