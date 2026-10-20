import 'package:blueway/features/camera/domain/capture_requirements.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('contrôle les bornes temporelles sans accepter le futur arbitraire', () {
    final now = DateTime.utc(2026, 10, 20);
    expect(isCaptureMeasurementFresh(null, now, maxCaptureGpsAge), isFalse);
    expect(
      isCaptureMeasurementFresh(
        now.subtract(maxCaptureGpsAge),
        now,
        maxCaptureGpsAge,
      ),
      isTrue,
    );
    expect(
      isCaptureMeasurementFresh(
        now.subtract(maxCaptureGpsAge + const Duration(milliseconds: 1)),
        now,
        maxCaptureGpsAge,
      ),
      isFalse,
    );
    expect(
      isCaptureMeasurementFresh(
        now.add(const Duration(seconds: 2)),
        now,
        maxCaptureGpsAge,
      ),
      isTrue,
    );
    expect(
      isCaptureMeasurementFresh(
        now.add(const Duration(seconds: 3)),
        now,
        maxCaptureGpsAge,
      ),
      isFalse,
    );
    expect(
      isCaptureMeasurementFresh(
        now.subtract(const Duration(seconds: 5)),
        now,
        maxCaptureSensorAge,
      ),
      isTrue,
    );
    expect(
      isCaptureMeasurementFresh(
        now.subtract(const Duration(seconds: 6)),
        now,
        maxCaptureSensorAge,
      ),
      isFalse,
    );
  });

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
