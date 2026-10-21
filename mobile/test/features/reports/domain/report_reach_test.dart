import 'package:blueway/features/reports/domain/report_reach.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const lat = 48.38, lon = -4.49;

  test('un point à 600 m reste à sa place', () {
    final near = ReportReach.destination(lat, lon, 1.0, 600);
    final kept = ReportReach.clamp(lat, lon, near.latitude, near.longitude);
    expect(kept.latitude, near.latitude);
    expect(kept.longitude, near.longitude);
  });

  test('un point à 3 km revient sur le bord, dans la même direction', () {
    final far = ReportReach.destination(lat, lon, 2.0, 3000);
    final kept = ReportReach.clamp(lat, lon, far.latitude, far.longitude);
    final edge = ReportReach.distance(lat, lon, kept.latitude, kept.longitude);
    expect(edge, closeTo(999, 0.5));
    expect(edge, lessThanOrEqualTo(ReportReach.radiusMeters));
    final sameAxis = ReportReach.destination(lat, lon, 2.0, 999);
    expect(kept.latitude, closeTo(sameAxis.latitude, 1e-7));
    expect(kept.longitude, closeTo(sameAxis.longitude, 1e-7));
  });

  test('le contour est fermé et à 1 km partout', () {
    final outline = ReportReach.outline(lat, lon);
    expect(outline.first[0], closeTo(outline.last[0], 1e-9));
    expect(outline.first[1], closeTo(outline.last[1], 1e-9));
    for (final point in outline) {
      expect(
        ReportReach.distance(lat, lon, point[1], point[0]),
        closeTo(1000, 0.5),
      );
    }
  });
}
