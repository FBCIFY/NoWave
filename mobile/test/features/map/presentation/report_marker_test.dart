import 'package:blueway/features/map/presentation/report_marker.dart';
import 'package:blueway/features/reports/domain/manual_report.dart';
import 'package:blueway/features/reports/presentation/report_category_style.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:ui' as ui;

void main() {
  for (final category in ReportCategory.values) {
    testWidgets(
      'badge PNG décodable et couleur correcte : ${category.apiValue}',
      (tester) async {
        final side = (ReportMarker.size * ReportMarker.pixelRatio).round();
        final pixels = await tester.runAsync(() async {
          final encoded = await ReportMarker.paintCategory(category);
          expect(encoded.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
          final codec = await ui.instantiateImageCodec(encoded);
          try {
            final frame = await codec.getNextFrame();
            try {
              expect(frame.image.width, side);
              expect(frame.image.height, side);
              final data = await frame.image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              return data!.buffer.asUint8List();
            } finally {
              frame.image.dispose();
            }
          } finally {
            codec.dispose();
          }
        });
        expect(pixels, hasLength(4 * side * side));
        final argb = category.color.toARGB32();
        final expected = [
          (argb >> 16) & 255,
          (argb >> 8) & 255,
          argb & 255,
          255,
        ];
        var hasCategoryColor = false;
        for (var i = 0; i < pixels!.length; i += 4) {
          expect(pixels[i], lessThanOrEqualTo(pixels[i + 3]));
          expect(pixels[i + 1], lessThanOrEqualTo(pixels[i + 3]));
          expect(pixels[i + 2], lessThanOrEqualTo(pixels[i + 3]));
          if (pixels[i] == expected[0] &&
              pixels[i + 1] == expected[1] &&
              pixels[i + 2] == expected[2] &&
              pixels[i + 3] == 255) {
            hasCategoryColor = true;
          }
        }
        expect(hasCategoryColor, true);
      },
    );
  }
}
