import 'dart:typed_data';

/// Mesures figées au moment de la photo. [toJson] donne l'objet `positioning`
/// attendu par `POST /api/v1/position-estimates` et `POST /api/v1/reports`.
class PhotoCaptureMeasurements {
  const PhotoCaptureMeasurements({
    required this.observerLongitude,
    required this.observerLatitude,
    required this.gpsAccuracyMeters,
    required this.azimuthDegrees,
    required this.inclinationDegrees,
    required this.cameraHeightMeters,
    required this.cameraHeightSource,
    required this.cameraHeightUncertaintyMeters,
    required this.capturedAt,
    this.focalLengthMm,
    this.zoomRatio,
  });

  final double observerLongitude;
  final double observerLatitude;
  final double gpsAccuracyMeters;

  /// Cap par rapport au nord vrai.
  final double azimuthDegrees;

  /// 0 à l'horizon, négatif vers l'eau.
  final double inclinationDegrees;
  final double cameraHeightMeters;
  final String cameraHeightSource;
  final double cameraHeightUncertaintyMeters;
  final DateTime capturedAt;

  /// Focale réelle de l'objectif, lue dans les EXIF de la photo (null si
  /// le téléphone ne la donne pas).
  final double? focalLengthMm;

  /// Zoom appliqué par l'app ; envoyé seulement s'il est connu.
  final double? zoomRatio;

  /// Mêmes mesures, complétées par la focale lue après la prise.
  PhotoCaptureMeasurements withFocalLength(double? focalLengthMm) =>
      PhotoCaptureMeasurements(
        observerLongitude: observerLongitude,
        observerLatitude: observerLatitude,
        gpsAccuracyMeters: gpsAccuracyMeters,
        azimuthDegrees: azimuthDegrees,
        inclinationDegrees: inclinationDegrees,
        cameraHeightMeters: cameraHeightMeters,
        cameraHeightSource: cameraHeightSource,
        cameraHeightUncertaintyMeters: cameraHeightUncertaintyMeters,
        capturedAt: capturedAt,
        focalLengthMm: focalLengthMm,
        zoomRatio: zoomRatio,
      );

  Map<String, Object?> toJson() => {
    'observer_position': {
      'type': 'Point',
      'coordinates': [observerLongitude, observerLatitude],
    },
    'gps_accuracy_m': gpsAccuracyMeters,
    // Le backend refuse 360 : l'azimut doit être dans [0, 360).
    'azimuth_deg': azimuthDegrees % 360,
    'inclination_deg': inclinationDegrees,
    'camera_height_m': cameraHeightMeters,
    'camera_height_source': cameraHeightSource,
    'camera_height_uncertainty_m': cameraHeightUncertaintyMeters,
    'focal_length_mm': ?focalLengthMm,
    'zoom_ratio': ?zoomRatio,
    'captured_at': capturedAt.toUtc().toIso8601String(),
  };
}

/// Photo prête à l'envoi et ses mesures. Gardée en mémoire tant que le
/// parcours est ouvert : pas de brouillon ni de reprise automatique.
class PhotoCapture {
  const PhotoCapture({required this.jpegBytes, required this.measurements});

  /// JPEG redressé, sans EXIF, d'au plus 500 000 octets.
  final Uint8List jpegBytes;
  final PhotoCaptureMeasurements measurements;
}
