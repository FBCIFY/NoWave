import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// PNG encodé et dimensions décodées pour les ponts natifs Mapbox 2.30.1.
///
/// Malgré la documentation générique de MbxImage.data (RGBA brut), cette
/// version utilise BitmapFactory.decodeByteArray sur Android et UIImage(data:)
/// sur iOS. Ces deux ponts attendent le PNG ; ils effectuent la conversion des
/// pixels eux-mêmes. Leur transmettre rawRgba rend l'image indécodable.
class MarineIconImage {
  static Future<MbxImage> load(String assetPath) async {
    final encoded = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(
      encoded.buffer.asUint8List(encoded.offsetInBytes, encoded.lengthInBytes),
    );
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        return MbxImage(
          width: image.width,
          height: image.height,
          data: encoded.buffer.asUint8List(
            encoded.offsetInBytes,
            encoded.lengthInBytes,
          ),
        );
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}
