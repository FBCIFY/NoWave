import 'package:blueway/features/map/presentation/report_marker.dart';
import 'package:blueway/features/reports/domain/manual_report.dart';
import 'package:blueway/features/reports/presentation/report_category_style.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final category in ReportCategory.values) {
    testWidgets('badge RGBA prémultiplié : ${category.apiValue}', (
      tester,
    ) async {
      final pixels = await tester.runAsync(
        () => ReportMarker.paintCategory(category),
      );
      final side = (ReportMarker.size * ReportMarker.pixelRatio).round();
      expect(pixels, hasLength(4 * side * side));
      final argb = category.color.toARGB32();
      final expected = [(argb >> 16) & 255, (argb >> 8) & 255, argb & 255, 255];
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
    });
  }
}
