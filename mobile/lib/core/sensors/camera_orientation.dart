import 'dart:math' as math;

/// Inclinaison de la caméra arrière, calculée à partir de la gravité mesurée
/// par l'accéléromètre (repère du téléphone, en m/s²) : -90° vers le sol,
/// 0° vers l'horizon, 90° vers le ciel.
///
/// La caméra arrière vise l'axe -z du téléphone ; à plat écran vers le ciel,
/// l'accéléromètre lit z ≈ +9,81. Retourne null si la mesure est nulle.
double? calculateCameraInclinationDegrees({
  required double x,
  required double y,
  required double z,
}) {
  final norm = math.sqrt(x * x + y * y + z * z);

  if (norm < 1e-6) {
    return null;
  }

  final verticalComponent = (-z / norm).clamp(-1.0, 1.0).toDouble();

  return math.asin(verticalComponent) * 180 / math.pi;
}
