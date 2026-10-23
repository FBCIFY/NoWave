import 'package:flutter_test/flutter_test.dart';
import 'package:blueway/core/location/coordinate_formatter.dart';

void main() {
  test('convertit une latitude nord', () {
    expect(formatDms(48.8566, isLatitude: true), '48° 51′ 24″ N');
  });

  test('convertit une longitude ouest', () {
    expect(formatDms(-4.49, isLatitude: false), '4° 29′ 24″ W');
  });

  test('convertit une latitude sud', () {
    expect(formatDms(-33.8688, isLatitude: true), '33° 52′ 8″ S');
  });

  test('reporte l’arrondi sur le degré suivant', () {
    expect(formatDms(12.999999, isLatitude: false), '13° 0′ 0″ E');
  });

  test('compas : format serré, longitude sur trois chiffres', () {
    expect(formatDmsCompact(43.4467, isLatitude: true), '43°26′48″N');
    expect(formatDmsCompact(6.7878, isLatitude: false), '006°47′16″E');
    expect(formatDmsCompact(-4.49, isLatitude: false), '004°29′24″W');
    expect(formatDmsCompact(-0.5, isLatitude: true), '00°30′00″S');
  });
}
