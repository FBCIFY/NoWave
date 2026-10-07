import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Caméra arrière vue par [CameraScreen]. L'interface permet de tester
/// l'écran sans téléphone ; [DeviceReportCamera] est la vraie.
///
/// Les erreurs sont des [CameraException], comme celles du plugin.
abstract interface class ReportCamera {
  /// Code de [CameraException] quand l'appareil n'a aucune caméra.
  static const noCameraCode = 'NoCamera';

  /// Code de [CameraException] quand l'appareil n'a pas de caméra arrière.
  static const noBackCameraCode = 'NoBackCamera';

  /// Code de [CameraException] quand la caméra a déjà été libérée.
  static const closedCode = 'CameraClosed';

  Future<void> initialize();

  /// Aperçu plein écran, une fois [initialize] terminé.
  Widget buildPreview();

  /// Prend une photo et renvoie le JPEG original, EXIF compris.
  Future<Uint8List> takePicture();

  Future<void> dispose();
}

class DeviceReportCamera implements ReportCamera {
  DeviceReportCamera({
    @visibleForTesting Future<List<CameraDescription>> Function()? findCameras,
    @visibleForTesting
    CameraController Function(CameraDescription camera)? createController,
  }) : _findCameras = findCameras ?? availableCameras,
       _createController = createController ?? _createDefaultController;

  final Future<List<CameraDescription>> Function() _findCameras;
  final CameraController Function(CameraDescription camera) _createController;

  /// Renseigné une fois la caméra prête, jamais après [dispose].
  CameraController? _controller;
  bool _isDisposed = false;

  static CameraController _createDefaultController(CameraDescription camera) =>
      CameraController(
        camera,
        // 1920 × 1080 : assez net pour reconnaître l'objet une fois réduit.
        ResolutionPreset.veryHigh,
        enableAudio: false,
      );

  /// À n'appeler qu'une fois : après [dispose], il faut une nouvelle caméra.
  /// Si l'écran se ferme entre-temps, le contrôleur créé est libéré ici.
  @override
  Future<void> initialize() async {
    final cameras = await _findCameras();

    // Écran fermé pendant la recherche : pas de contrôleur à créer.
    if (_isDisposed) return;

    if (cameras.isEmpty) {
      throw CameraException(ReportCamera.noCameraCode, null);
    }

    final backCamera = cameras
        .where((camera) => camera.lensDirection == CameraLensDirection.back)
        .firstOrNull;

    if (backCamera == null) {
      throw CameraException(ReportCamera.noBackCameraCode, null);
    }

    final controller = _createController(backCamera);

    try {
      await controller.initialize();

      // L'interface reste en portrait : sans ce verrou, le plugin tourne
      // l'aperçu quand on met le téléphone à l'horizontale.
      if (!_isDisposed) {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      }
    } catch (_) {
      await _disposeQuietly(controller);
      // L'écran fermé n'a plus d'erreur à afficher.
      if (_isDisposed) return;
      rethrow;
    }

    // Écran fermé pendant l'ouverture : dispose() n'a pas vu ce contrôleur.
    if (_isDisposed) {
      await _disposeQuietly(controller);
      return;
    }

    _controller = controller;
  }

  /// Une ouverture ratée fait aussi échouer dispose() du plugin, qui attend
  /// la fin de l'ouverture.
  static Future<void> _disposeQuietly(CameraController controller) async {
    try {
      await controller.dispose();
    } catch (_) {
      // Rien à libérer de plus.
    }
  }

  @override
  Widget buildPreview() => _FullScreenPreview(controller: _controller!);

  @override
  Future<Uint8List> takePicture() async {
    final controller = _controller;
    // Caméra libérée (application passée en arrière-plan) : même erreur
    // qu'un échec du plugin.
    if (controller == null) {
      throw CameraException(ReportCamera.closedCode, null);
    }
    final photo = await controller.takePicture();
    final bytes = await photo.readAsBytes();
    await _deleteOriginalPhoto(photo.path);
    return bytes;
  }

  /// L'original garde la position GPS dans ses EXIF : seule la version
  /// nettoyée reste, en mémoire.
  Future<void> _deleteOriginalPhoto(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // Fichier temporaire de l'app : le système finira par le supprimer.
    }
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    final controller = _controller;
    _controller = null;
    if (controller != null) await _disposeQuietly(controller);
  }
}

/// Aperçu recadré pour remplir l'écran. Le recadrage est centré : le réticule
/// vise le centre de la photo, qui montre un peu plus que l'aperçu.
class _FullScreenPreview extends StatelessWidget {
  const _FullScreenPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;

    if (previewSize == null) {
      return CameraPreview(controller);
    }

    // previewSize est donné en paysage : largeur et hauteur sont inversées.
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewSize.height,
          height: previewSize.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}
