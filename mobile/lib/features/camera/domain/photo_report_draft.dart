import 'photo_capture.dart';
import 'position_estimate.dart';

/// Résultat de l'écran caméra, rendu à la carte : la photo, ses mesures et
/// la position estimée par le backend (null s'il n'a pas pu l'estimer).
class PhotoReportDraft {
  const PhotoReportDraft({required this.capture, required this.estimate});

  final PhotoCapture capture;
  final PositionEstimate? estimate;

  /// Point proposé sur la carte : l'estimation, sinon la position du
  /// téléphone au moment de la photo.
  double get initialLongitude =>
      estimate?.longitude ?? capture.measurements.observerLongitude;

  double get initialLatitude =>
      estimate?.latitude ?? capture.measurements.observerLatitude;
}
