import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Taille maximale d'une photo acceptée par le backend.
const int maxReportPhotoBytes = 500000;

/// Plus grands côtés essayés, du plus net au plus léger.
const List<int> _maxDimensions = [1600, 1200, 800];

/// Qualités JPEG essayées pour chaque taille.
const List<int> _qualities = [85, 70, 55];

/// Prépare la photo pour l'envoi : orientation appliquée aux pixels, EXIF
/// supprimés (dont la position GPS du téléphone), JPEG d'au plus [maxBytes]
/// octets. Calcul lourd : à lancer hors du fil de l'interface.
///
/// Lève une [FormatException] si l'image est illisible ou reste trop lourde.
Uint8List prepareReportJpeg(
  Uint8List bytes, {
  int maxBytes = maxReportPhotoBytes,
}) {
  img.Image? decoded;

  try {
    // La caméra fournit toujours un JPEG.
    decoded = img.decodeJpg(bytes);
  } catch (_) {
    // Un fichier tronqué peut faire échouer le décodeur au lieu de null.
  }

  if (decoded == null) {
    throw const FormatException('Photo illisible.');
  }

  // Le téléphone enregistre souvent l'image couchée avec une consigne de
  // rotation dans les EXIF : on tourne les pixels avant de retirer les EXIF.
  final upright = img.bakeOrientation(decoded);

  for (final maxDimension in _maxDimensions) {
    final resized = _fitWithin(upright, maxDimension);
    resized.exif = img.ExifData();

    for (final quality in _qualities) {
      final jpeg = img.encodeJpg(
        resized,
        quality: quality,
        chroma: img.JpegChroma.yuv420,
      );

      if (jpeg.length <= maxBytes) {
        return jpeg;
      }
    }
  }

  throw const FormatException('Photo trop lourde.');
}

img.Image _fitWithin(img.Image image, int maxDimension) {
  if (math.max(image.width, image.height) <= maxDimension) {
    return img.Image.from(image);
  }

  return image.width >= image.height
      ? img.copyResize(
          image,
          width: maxDimension,
          interpolation: img.Interpolation.average,
        )
      : img.copyResize(
          image,
          height: maxDimension,
          interpolation: img.Interpolation.average,
        );
}
