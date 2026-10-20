import 'dart:math' as math;

/// Cap magnétique du téléphone pour la carte, avec la convention de posture
/// du LocationCompassEngine Android de Mapbox 11.30.1 : haut de l'écran à
/// plat, direction devant l'écran quand il est relevé de plus de 45°.
///
/// Suivre +Y jusqu'à la verticale rend atan2(R[1], R[4]) singulier : le
/// roulis est alors interprété comme un changement de cap. On choisit un axe
/// dont la projection horizontale reste exploitable. Ces changements d'axes
/// sont des transformations géométriques, sans correction angulaire fixe.
/// La visée photographique NW-150 reste toujours -Z, quelle que soit la pose.
double? androidDeviceHeading(List<double> matrix, {int displayRotation = 0}) {
  if (matrix.length != 9) {
    throw ArgumentError.value(matrix, 'matrix', '9 valeurs attendues');
  }
  if (!matrix.every((value) => value.isFinite)) return null;
  final (column, sign) = switch (displayRotation) {
    0 => (1, 1.0), // +Y : portrait naturel
    1 => (0, 1.0), // +X : écran tourné de 90°
    2 => (1, -1.0), // -Y : écran tourné de 180°
    3 => (0, -1.0), // -X : écran tourné de 270°
    _ => throw ArgumentError.value(displayRotation, 'displayRotation'),
  };
  final screenTopUp = sign * matrix[6 + column];
  const uprightThreshold = math.sqrt1_2;
  final double east;
  final double north;
  if (screenTopUp > uprightThreshold) {
    east = -matrix[2];
    north = -matrix[5];
  } else if (screenTopUp < -uprightThreshold) {
    east = matrix[2];
    north = matrix[5];
  } else {
    // Écran face au sol : Mapbox inverse le haut de l'écran.
    final facing = matrix[8] < 0 ? -sign : sign;
    east = facing * matrix[column];
    north = facing * matrix[3 + column];
  }
  if (east * east + north * north < 1e-12) return null;
  return (math.atan2(east, north) * 180 / math.pi) % 360;
}
