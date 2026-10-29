import 'package:blueway/features/reports/presentation/report_detail_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('écrit la distance en milles nautiques', () {
    expect(formatNauticalMiles(50), '< 0,1 NM');
    expect(formatNauticalMiles(4444.8), '2,4 NM');
    expect(formatNauticalMiles(22224), '12 NM');
  });

  test('donne la direction la plus proche sur huit points', () {
    expect(compassPoint(0), 'N');
    expect(compassPoint(44), 'NE');
    expect(compassPoint(-90), 'O');
    expect(compassPoint(200), 'S');
    expect(compassPoint(350), 'N');
  });

  test('écrit la date par rapport à aujourd’hui', () {
    final now = DateTime(2026, 10, 5, 14);

    expect(
      formatDayTime(DateTime(2026, 10, 5, 9, 5), now: now),
      'aujourd’hui à 09:05',
    );
    expect(
      formatDayTime(DateTime(2026, 10, 4, 23, 30), now: now),
      'hier à 23:30',
    );
    expect(formatDayTime(DateTime(2026, 10, 6, 1), now: now), 'demain à 01:00');
    expect(
      formatDayTime(DateTime(2026, 9, 28, 8), now: now),
      'le 28/09/2026 à 08:00',
    );
  });
}
