import 'package:flutter_test/flutter_test.dart';

import 'package:blueway/core/device/device_position.dart';

void main() {
  DevicePosition position({
    double latitude = 43.2965,
    double longitude = 5.3698,
    double accuracyM = 12,
    double? headingDeg,
  }) {
    return DevicePosition(
      latitude: latitude,
      longitude: longitude,
      accuracyM: accuracyM,
      headingDeg: headingDeg,
      measuredAt: DateTime.utc(2026, 10, 5, 8, 30),
    );
  }

  test('toJson suit le contrat du backend (GeoJSON lon, lat et UTC)', () {
    final json = DevicePosition(
      latitude: 43.2965,
      longitude: 5.3698,
      accuracyM: 12.5,
      headingDeg: 270,
      measuredAt: DateTime.parse('2026-10-05T10:30:00+02:00'),
    ).toJson();

    expect(json, {
      'position': {
        'type': 'Point',
        'coordinates': [5.3698, 43.2965],
      },
      'accuracy_m': 12.5,
      'heading_deg': 270.0,
      'measured_at': '2026-10-05T08:30:00.000Z',
    });
  });

  test('toJson envoie un cap null quand il est inconnu', () {
    expect(position().toJson()['heading_deg'], isNull);
  });

  test('accepte une précision jusqu’à 50 m inclus', () {
    expect(position(accuracyM: 0).isUsable, isTrue);
    expect(position(accuracyM: 50).isUsable, isTrue);
  });

  test('refuse une précision au-delà de 50 m ou invalide', () {
    expect(position(accuracyM: 50.1).isUsable, isFalse);
    expect(position(accuracyM: -1).isUsable, isFalse);
    expect(position(accuracyM: double.nan).isUsable, isFalse);
    expect(position(accuracyM: double.infinity).isUsable, isFalse);
  });

  test('refuse des coordonnées hors limites', () {
    expect(position(latitude: 91).isUsable, isFalse);
    expect(position(longitude: -181).isUsable, isFalse);
    expect(position(latitude: double.nan).isUsable, isFalse);
  });
}
