import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Dessins du curseur NoWave : un chevron couché au pied d'un mât qui porte
/// le pavillon du bateau. Le chevron indique le cap dans le plan de la
/// carte ; le mât reste debout face à l'écran, sous les pastilles des
/// signalements qui passent devant son pied.
///
/// Mapbox n'affiche pas de widget : chaque dessin est encodé en PNG, à la
/// densité de l'écran.
abstract final class LocationMast {
  static const navy = Color(0xFF172554);

  /// Pavillon uni quand le bateau n'en a pas, ou un code inconnu.
  static const noFlag = Color(0xFF2563EB);

  /// Côté de l'image du chevron, centrée sur la position, en points.
  static const chevronSide = 48.0;

  /// Taille du chevron loin de la carte détaillée.
  static const smallScale = .75;

  /// Image du mât, en points : le mât est au milieu, le pavillon à droite.
  static const mastWidth = 60.0;
  static const mastHeight = 62.0;

  /// Place sous le pied du mât, pour le bout arrondi et l'ombre.
  static const footMargin = 4.0;

  static const _mastLength = 50.0;
  static const _flagWidth = 23.0;
  static const _flagHeight = 15.0;
  static const _flagColumns = 24;
  static const _flagShade = .22;

  /// Pavillon « retombant » : décalage vertical, en points, pour u de 0
  /// (mât) à 1 (bord libre). Il tombe vers le bout avec une légère ondulation.
  static double _flagDrop(double u) =>
      3.2 * u * u + .7 * math.sin(u * 2 * math.pi);

  /// Hauteur relative : le bord libre est un peu plus court.
  static double _flagSpan(double u) => 1 - .1 * u;

  /// Image du pavillon d'un code ISO à deux lettres, ou null s'il n'existe
  /// pas dans `assets/flags/`.
  static Future<ui.Image?> loadFlag(String? country) async {
    final code = country?.trim().toLowerCase() ?? '';
    if (!RegExp(r'^[a-z]{2}$').hasMatch(code)) return null;
    final ByteData data;
    try {
      data = await rootBundle.load('assets/flags/$code.png');
    } catch (_) {
      return null;
    }
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  /// Chevron du cap, pointé vers le nord, avec le pied du mât au centre.
  static Future<MbxImage> chevron(double pixelRatio, {double scale = 1}) =>
      _encode(pixelRatio, chevronSide, chevronSide, (canvas) {
        canvas
          ..translate(chevronSide / 2, chevronSide / 2)
          ..scale(scale);
        final arrow = Path()
          ..moveTo(0, -18)
          ..lineTo(13.5, 12.5)
          ..lineTo(0, 5.5)
          ..lineTo(-13.5, 12.5)
          ..close();
        canvas.drawShadow(arrow, Colors.black, 2, false);
        _outlined(canvas, arrow, navy);
        canvas.drawCircle(Offset.zero, 3.4, Paint()..color = Colors.white);
      });

  /// Sans cap : un disque sous le pied du mât.
  static Future<MbxImage> dot(double pixelRatio) =>
      _encode(pixelRatio, chevronSide, chevronSide, (canvas) {
        final disc = Path()
          ..addOval(
            Rect.fromCircle(
              center: const Offset(chevronSide / 2, chevronSide / 2),
              radius: 10,
            ),
          );
        canvas.drawShadow(disc, Colors.black, 2, false);
        _outlined(canvas, disc, navy);
        canvas.drawCircle(
          const Offset(chevronSide / 2, chevronSide / 2),
          3.4,
          Paint()..color = Colors.white,
        );
      });

  /// Mât et pavillon plié par le vent ; [flag] null donne un pavillon bleu
  /// uni.
  static Future<MbxImage> mast(double pixelRatio, ui.Image? flag) =>
      _encode(pixelRatio, mastWidth, mastHeight, (canvas) {
        const foot = Offset(mastWidth / 2, mastHeight - footMargin);
        const x = mastWidth / 2;
        const top = mastHeight - footMargin - _mastLength;
        // Sous la boule du sommet, sans la toucher.
        const hoist = Offset(x + 1.2, top + 6);
        final shadow = Path()
          ..addRect(Rect.fromLTRB(x - 1.2, top, x + 1.2, foot.dy))
          ..addRect(Rect.fromLTWH(hoist.dx, hoist.dy, _flagWidth, _flagHeight));
        canvas.drawShadow(shadow, Colors.black, 3, false);
        for (final (color, width) in [(Colors.white, 5.0), (navy, 2.2)]) {
          canvas.drawLine(
            const Offset(x, top),
            foot,
            Paint()
              ..color = color
              ..strokeWidth = width
              ..strokeCap = StrokeCap.round,
          );
        }
        _outlined(
          canvas,
          Path()..addOval(
            Rect.fromCircle(center: const Offset(x, top - 2), radius: 2.2),
          ),
          navy,
        );
        _paintFlag(canvas, flag, hoist);
      });

  /// Rectangle déformé en maillage, le pavillon plaqué dessus, puis les
  /// plis : plus sombre où le tissu descend, plus clair où il remonte.
  static void _paintFlag(Canvas canvas, ui.Image? flag, Offset hoist) {
    final tops = <Offset>[], bottoms = <Offset>[];
    for (var i = 0; i <= _flagColumns; i++) {
      final u = i / _flagColumns;
      final x = hoist.dx + u * _flagWidth;
      final middle = hoist.dy + _flagHeight / 2 + _flagDrop(u);
      final half = _flagHeight * _flagSpan(u) / 2;
      tops.add(Offset(x, middle - half));
      bottoms.add(Offset(x, middle + half));
    }
    final outline = Path()..addPolygon([...tops, ...bottoms.reversed], true);
    canvas.drawPath(
      outline,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round,
    );
    if (flag == null) {
      canvas.drawPath(outline, Paint()..color = noFlag);
    } else {
      final positions = <Offset>[], texture = <Offset>[], indices = <int>[];
      for (var i = 0; i <= _flagColumns; i++) {
        final tx = flag.width * i / _flagColumns;
        positions
          ..add(tops[i])
          ..add(bottoms[i]);
        texture
          ..add(Offset(tx, 0))
          ..add(Offset(tx, flag.height.toDouble()));
        if (i < _flagColumns) {
          final k = i * 2;
          indices.addAll([k, k + 1, k + 2, k + 1, k + 3, k + 2]);
        }
      }
      canvas.drawVertices(
        ui.Vertices(
          VertexMode.triangles,
          positions,
          textureCoordinates: texture,
          indices: indices,
        ),
        BlendMode.srcOver,
        Paint()
          ..shader = ImageShader(
            flag,
            TileMode.clamp,
            TileMode.clamp,
            Matrix4.identity().storage,
            filterQuality: FilterQuality.medium,
          ),
      );
    }
    final colors = <Color>[], stops = <double>[];
    for (var i = 0; i <= _flagColumns; i++) {
      final u = i / _flagColumns;
      final slope =
          (_flagDrop(math.min(u + .02, 1)) - _flagDrop(math.max(u - .02, 0))) /
          .04 /
          _flagHeight;
      final shade = (slope * _flagShade * 2).clamp(-_flagShade, _flagShade);
      colors.add(
        shade > 0
            ? Colors.black.withValues(alpha: shade)
            : Colors.white.withValues(alpha: -shade * .8),
      );
      stops.add(u);
    }
    canvas
      ..save()
      ..clipPath(outline)
      ..drawRect(
        outline.getBounds(),
        Paint()
          ..shader = ui.Gradient.linear(
            hoist,
            hoist + const Offset(_flagWidth, 0),
            colors,
            stops,
          ),
      )
      ..restore();
  }

  /// Contour blanc de 2 points à l'extérieur, fond plein : le style des
  /// pastilles.
  static void _outlined(Canvas canvas, Path path, Color fill) => canvas
    ..drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round,
    )
    ..drawPath(path, Paint()..color = fill);

  /// Le pont Android de mapbox_maps_flutter appelle
  /// BitmapFactory.decodeByteArray : transmettre une image PNG encodée.
  static Future<MbxImage> _encode(
    double pixelRatio,
    double width,
    double height,
    void Function(Canvas canvas) draw,
  ) async {
    final recorder = ui.PictureRecorder();
    draw(Canvas(recorder)..scale(pixelRatio));
    final pixelWidth = (width * pixelRatio).round();
    final pixelHeight = (height * pixelRatio).round();
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(pixelWidth, pixelHeight);
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        return MbxImage(
          width: pixelWidth,
          height: pixelHeight,
          data: png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        );
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }
}
