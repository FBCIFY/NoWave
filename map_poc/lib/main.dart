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
  MapLibreMap.webLibrarySource = const MapLibreJsSource.cdn();
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
  Timer? _loadTimer;
  String? _error;
  bool _ready = false;
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
    });
    try {
      final style = await MapStyle.load(_client, Uri.parse(styleUrl));
      if (!mounted || generation != _generation) return;
      setState(() {
        _style = style;
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
      body: Column(
        children: [
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
                    onStyleLoadedCallback: () {
                      _loadTimer?.cancel();
                      if (mounted) setState(() => _ready = true);
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
