// Recette NW-197 : flutter run --profile -t tool/camera_device_validation.dart
// -d <device>. Pas de Firebase, de backend, de galerie ou de photo persistée.
import 'dart:async';
import 'dart:convert';

import 'package:blueway/features/camera/domain/report_jpeg.dart';
import 'package:blueway/features/camera/presentation/report_camera.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: _Validation()));

class _Validation extends StatefulWidget {
  const _Validation();
  @override
  State<_Validation> createState() => _ValidationState();
}

class _ValidationState extends State<_Validation> with WidgetsBindingObserver {
  DeviceReportCamera? _camera;
  Future<void>? _closing;
  Uint8List? _jpeg;
  String _status = 'Ouverture…';
  bool _ready = false;
  bool _busy = false;
  int _opening = 0;
  int _capture = 0;
  String _scene = 'Loin initial';

  void _record(Map<String, Object?> event) {
    // Seulement des métadonnées optiques : ni EXIF GPS ni image dans le log.
    // ignore: avoid_print
    print(
      'CAMERA_DEVICE_VALIDATION ${jsonEncode({'at': DateTime.now().toUtc().toIso8601String(), ...event})}',
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_open());
  }

  Future<void> _open() async {
    final opening = ++_opening;
    try {
      await _closing;
      if (!mounted || opening != _opening) return;
      // Injection de diagnostic pour observer l'inventaire sans changer la
      // sélection ni le contrôleur de production.
      final camera = DeviceReportCamera(
        // ignore: invalid_use_of_visible_for_testing_member
        findCameras: () async {
          final cameras = await availableCameras();
          _record({
            'event': 'inventory',
            'opening': opening,
            'cameras': cameras
                .map(
                  (c) => {
                    'name': c.name,
                    'direction': c.lensDirection.name,
                    'lens_type': c.lensType.name,
                    'sensor_orientation': c.sensorOrientation,
                  },
                )
                .toList(),
          });
          final selected = cameras
              .where((c) => c.lensDirection == CameraLensDirection.back)
              .firstOrNull;
          _record({
            'event': 'selection',
            'opening': opening,
            'name': selected?.name,
            'lens_type': selected?.lensType.name,
          });
          return cameras;
        },
      );
      _camera = camera;
      await camera.initialize();
      if (!mounted || opening != _opening) return;
      _record({'event': 'ready', 'opening': opening});
      setState(() {
        _ready = true;
        _status = 'Viser loin, puis près, puis loin. Capturer chaque étape.';
      });
    } catch (error) {
      _record({
        'event': 'error',
        'code': error is CameraException
            ? error.code
            : error.runtimeType.toString(),
      });
      if (mounted) setState(() => _status = 'Ouverture impossible : $error');
    }
  }

  Future<void> _close() async {
    _opening++;
    final camera = _camera;
    _camera = null;
    _ready = false;
    await camera?.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _record({'event': 'lifecycle', 'state': state.name});
    if (state == AppLifecycleState.inactive) {
      _closing = _close();
    } else if (state == AppLifecycleState.resumed && _camera == null) {
      unawaited(_open());
    }
  }

  Future<void> _takePicture() async {
    final camera = _camera;
    if (!_ready || _busy || camera == null) return;
    setState(() => _busy = true);
    try {
      final original = await camera.takePicture();
      final focal = readFocalLengthMm(original);
      final prepared = await compute(prepareReportJpeg, original);
      _record({
        'event': 'capture',
        'scene': _scene,
        'number': ++_capture,
        'focal_length_mm': focal,
        'original_bytes': original.length,
        'prepared_bytes': prepared.length,
        'prepared_focal_length_mm': readFocalLengthMm(prepared),
      });
      if (!mounted) return;
      setState(() {
        _jpeg = prepared;
        _status =
            'Photo $_capture — focale $focal mm. Vérifier la netteté au centre (zoom possible).';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Capture impossible : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('NW-197 — recette caméra')),
    body: Column(
      children: [
        Padding(padding: const EdgeInsets.all(12), child: Text(_status)),
        DropdownButton<String>(
          value: _scene,
          items: [
            for (final scene in const [
              'Loin initial',
              'Près',
              'Retour loin',
              'Après réouverture',
              'Après arrière-plan',
            ])
              DropdownMenuItem(value: scene, child: Text(scene)),
          ],
          onChanged: _busy || _jpeg != null
              ? null
              : (value) => setState(() => _scene = value!),
        ),
        Expanded(
          child: _jpeg != null
              ? InteractiveViewer(maxScale: 8, child: Image.memory(_jpeg!))
              : _ready && _camera != null
              ? _camera!.buildPreview()
              : const Center(child: CircularProgressIndicator()),
        ),
        SafeArea(
          child: Wrap(
            spacing: 12,
            children: [
              if (_jpeg != null)
                for (final sharp in [true, false])
                  TextButton(
                    onPressed: () {
                      _record({
                        'event': 'visual_observation',
                        'capture': _capture,
                        'scene': _scene,
                        'sharp': sharp,
                        'observer': 'device_operator',
                      });
                      setState(() {
                        _jpeg = null;
                        _status =
                            'Observation enregistrée : ${sharp ? "nette" : "floue"}.';
                      });
                    },
                    child: Text(sharp ? 'Nette' : 'Floue'),
                  ),
              FilledButton(
                onPressed: _ready && !_busy && _jpeg == null
                    ? _takePicture
                    : null,
                child: const Text('Capturer'),
              ),
              TextButton(
                onPressed: _jpeg != null
                    ? () => setState(() => _jpeg = null)
                    : null,
                child: const Text('Retour aperçu'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() {
                          _ready = false;
                          _jpeg = null;
                        });
                        _closing = _close();
                        await _open();
                      },
                child: const Text('Réouvrir'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
