import 'dart:io';

import 'package:camera/camera.dart';
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

  Future<void> initialize();

  /// Aperçu plein écran, une fois [initialize] terminé.
  Widget buildPreview();

  /// Prend une photo et renvoie le JPEG original, EXIF compris.
  Future<Uint8List> takePicture();

  Future<void> dispose();
}

class DeviceReportCamera implements ReportCamera {
  CameraController? _controller;
  bool _isDisposed = false;

  @override
  Future<void> initialize() async {
    final cameras = await availableCameras();

    if (cameras.isEmpty) {
      throw CameraException(ReportCamera.noCameraCode, null);
    }

    final backCamera = cameras
        .where((camera) => camera.lensDirection == CameraLensDirection.back)
        .firstOrNull;

    if (backCamera == null) {
      throw CameraException(ReportCamera.noBackCameraCode, null);
    }

    final controller = CameraController(
      backCamera,
      // 1920 × 1080 : assez net pour reconnaître l'objet une fois réduit.
      ResolutionPreset.veryHigh,
      enableAudio: false,
    );

    _controller = controller;
    await controller.initialize();

    // Écran fermé pendant l'ouverture : dispose() a déjà libéré la caméra.
    if (_isDisposed) return;

    // L'interface reste en portrait : sans ce verrou, le plugin tourne
    // l'aperçu quand on met le téléphone à l'horizontale.
    await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
  }

  @override
  Widget buildPreview() => _FullScreenPreview(controller: _controller!);

  @override
  Future<Uint8List> takePicture() async {
    final photo = await _controller!.takePicture();
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
    await _controller?.dispose();
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
