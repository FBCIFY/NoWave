import 'package:blueway/features/camera/domain/capture_requirements.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('autorise une précision nulle', () {
    expect(isCaptureGpsAccuracySufficient(0), isTrue);
  });

  for (final accuracy in [
    -0.1,
    -1.0,
    double.negativeInfinity,
    double.infinity,
    double.nan,
  ]) {
    test('refuse une précision invalide : $accuracy', () {
      expect(isCaptureGpsAccuracySufficient(accuracy), isFalse);
    });
  }

  test('autorise exactement 50 mètres de précision', () {
    expect(isCaptureGpsAccuracySufficient(50), isTrue);
  });

  test('refuse une précision supérieure à 50 mètres', () {
    expect(isCaptureGpsAccuracySufficient(50.1), isFalse);
  });

  test('refuse une précision absente', () {
    expect(isCaptureGpsAccuracySufficient(null), isFalse);
  });
}
