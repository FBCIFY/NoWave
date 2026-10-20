import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../reports/domain/manual_report.dart';
import '../../reports/presentation/report_category_style.dart';

/// Badge d'un signalement sur la carte : le carré arrondi du choix de
/// catégorie, avec son icône, posé sur une petite ombre.
///
/// Mapbox n'affiche pas de widget : le badge est dessiné une fois en pixels RGBA,
/// puis ajouté au style comme image.
abstract final class ReportMarker {
  /// Résolution du dessin : net sur les écrans les plus denses.
  static const pixelRatio = 3.0;

  /// Côté du carré, en points.
  static const _side = 30.0;
  static const _radius = Radius.circular(9);
  static const _borderWidth = 2.0;
  static const _iconSize = 18.0;

  /// Place laissée autour du carré pour que l'ombre ne soit pas coupée.
  static const _margin = 5.0;
  static const _shadowElevation = 3.0;

  /// Taille de l'image, ombre comprise, en points.
  static const size = _side + 2 * _margin;

  static String imageId(ReportCategory category) =>
      'nowave-report-${category.apiValue}';

  // Only successful renders are cached; a failed render can be retried.
  // Pixels survive style reloads, while registration belongs to each style.
  static final _categoryPixels = <ReportCategory, Uint8List>{};

  static Future<Uint8List> paintCategory(ReportCategory category) async {
    final cached = _categoryPixels[category];
    if (cached != null) return cached;
    final pixels = await paint(icon: category.icon, color: category.color);
    _categoryPixels[category] = pixels;
    return pixels;
  }

  /// Pixels RGBA prémultipliés attendus par MbxImage (4 octets par pixel).
  static Future<Uint8List> paint({
    required IconData icon,
    required Color color,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);

    final badge = RRect.fromRectAndRadius(
      const Rect.fromLTWH(_margin, _margin, _side, _side),
      _radius,
    );
    canvas
      ..drawShadow(
        Path()..addRRect(badge),
        Colors.black,
        _shadowElevation,
        false,
      )
      ..drawRRect(badge, Paint()..color = Colors.white)
      ..drawRRect(badge.deflate(_borderWidth), Paint()..color = color);

    final glyph = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: _iconSize,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    glyph.paint(
      canvas,
      badge.center - Offset(glyph.width / 2, glyph.height / 2),
    );
    glyph.dispose();

    final pixels = (size * pixelRatio).round();
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(pixels, pixels);
      try {
        final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return rgba!.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }
}
