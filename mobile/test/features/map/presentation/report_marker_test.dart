import 'package:blueway/features/map/presentation/report_marker.dart';
import 'package:blueway/features/reports/domain/manual_report.dart';
import 'package:blueway/features/reports/presentation/report_category_style.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  for (final category in ReportCategory.values) {
    testWidgets(
      'badge PNG décodable, alpha et couleur : ${category.apiValue}',
      (tester) async {
        final bytes = await tester.runAsync(
          () => ReportMarker.paintCategory(category),
        );
        expect(bytes!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final decoded = img.decodePng(bytes)!;
        final side = (ReportMarker.size * ReportMarker.pixelRatio).round();
        expect(decoded.width, side);
        expect(decoded.height, side);
        expect(decoded.getPixel(0, 0).a, 0);
        final argb = category.color.toARGB32();
        final red = (argb >> 16) & 255;
        final green = (argb >> 8) & 255;
        final blue = argb & 255;
        expect(
          decoded.any(
            (p) => p.r == red && p.g == green && p.b == blue && p.a == 255,
          ),
          true,
        );
        expect(
          decoded.any(
            (p) => p.r == 255 && p.g == 255 && p.b == 255 && p.a == 255,
          ),
          true,
        );
        expect(
          identical(bytes, await ReportMarker.paintCategory(category)),
          true,
        );
      },
    );
  }
}
