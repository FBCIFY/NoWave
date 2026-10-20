import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/map/cloud_passage_controller.dart';

/// Six textured banks on three perspective planes, below all map controls.
/// Geographic NASA clouds remain in Mapbox; this is a decorative near-camera
/// passage, not a weather layer or a claim about local cloud coverage.
class CloudPassage extends StatefulWidget {
  const CloudPassage({super.key, required this.camera});

  final CloudPassageController camera;

  @override
  State<CloudPassage> createState() => _CloudPassageState();
}

class _CloudPassageState extends State<CloudPassage>
    with WidgetsBindingObserver {
  ui.Image? _atlas;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAtlas();
  }

  Future<void> _loadAtlas() async {
    try {
      final data = await rootBundle.load(
        'assets/globe/cloud-passage-atlas.png',
      );
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      ui.FrameInfo frame;
      try {
        frame = await codec.getNextFrame();
      } finally {
        codec.dispose();
      }
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _atlas = frame.image);
    } catch (error) {
      // The map remains fully usable if the optional asset cannot be decoded.
      debugPrint('Traversée nuageuse indisponible : $error');
    }
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _atlas?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final atlas = _atlas;
    final reduceMotion =
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;
    if (atlas == null || reduceMotion) return const SizedBox.shrink();
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: CloudPassagePainter(camera: widget.camera, atlas: atlas),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class CloudPassagePainter extends CustomPainter {
  CloudPassagePainter({required this.camera, required this.atlas})
    : super(repaint: camera);

  final CloudPassageController camera;
  final ui.Image atlas;
  final _paint = Paint()..filterQuality = FilterQuality.low;

  // Coordinates in viewport-width units, around a common vanishing point.
  // Different atlas cells/angles prevent an obvious repeating cloud stamp.
  static const _banks = [
    (x: -.42, y: -.58, width: 1.85, tile: 0, angle: -.32),
    (x: .52, y: .52, width: 1.8, tile: 1, angle: .45),
    (x: .5, y: -.38, width: 1.55, tile: 1, angle: -.6),
    (x: -.52, y: .56, width: 1.65, tile: 2, angle: .7),
    (x: -.48, y: -.4, width: 1.35, tile: 2, angle: .28),
    (x: .62, y: .65, width: 1.45, tile: 0, angle: -.8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (!camera.visible || size.isEmpty) return;
    final unit = size.shortestSide;
    final lon = camera.longitude * math.pi / 180;
    final lat = camera.latitude * math.pi / 180;
    final bearing = camera.bearing * math.pi / 180;
    final focal = Offset(size.width * .5, size.height * .48);
    final tileSize = atlas.height.toDouble();
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var i = 0; i < CloudPassagePlane.planes.length; i++) {
      final plane = CloudPassagePlane.planes[i];
      final opacity = plane.opacityAt(camera.zoom);
      if (opacity <= .001) continue;
      final scale = plane.scaleAt(camera.zoom);
      final parallax = (i + 1) * .065;
      final driftX = math.sin(lon) * parallax;
      final driftY = math.sin(lat) * parallax + camera.pitch / 90 * parallax;
      _paint.color = Color.fromRGBO(255, 255, 255, opacity);
      for (var j = i * 2; j < i * 2 + 2; j++) {
        final bank = _banks[j];
        final width = unit * bank.width * scale;
        final position =
            focal +
            Offset(
              (bank.x + driftX) * unit * scale,
              (bank.y + driftY) * unit * scale,
            );
        canvas.save();
        canvas.translate(position.dx, position.dy);
        // A periodic offset avoids a jump when Mapbox wraps 359° to 0°.
        canvas.rotate(bank.angle - math.sin(bearing) * parallax);
        canvas.drawImageRect(
          atlas,
          Rect.fromLTWH(bank.tile * tileSize, 0, tileSize, tileSize),
          Rect.fromCenter(center: Offset.zero, width: width, height: width),
          _paint,
        );
        canvas.restore();
      }
    }
    canvas.restore();
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(CloudPassagePainter oldDelegate) =>
      oldDelegate.atlas != atlas || oldDelegate.camera != camera;
}
