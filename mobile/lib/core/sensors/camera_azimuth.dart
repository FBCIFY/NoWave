import 'dart:math' as math;

/// Direction visée par la caméra arrière dans le repère terrestre d'Android :
/// est, nord (magnétique) et haut. Vecteur unitaire.
typedef CameraAxis = ({double east, double north, double up});

/// En dessous de cette part horizontale (caméra à moins de ~6° de la
/// verticale), la direction horizontale n'a plus de sens : l'azimut saute
/// au moindre tremblement.
const double minHorizontalAxisComponent = 0.1;

/// Axe de visée de la caméra arrière à partir de la matrice de rotation
/// Android (`SensorManager.getRotationMatrixFromVector`, 9 valeurs ligne par
/// ligne), qui fait passer un vecteur du repère du téléphone au repère
/// terrestre.
///
/// Repère du téléphone : x vers la droite de l'écran, y vers son haut, z
/// sortant de l'écran. La caméra arrière vise -z, c'est-à-dire la troisième
/// colonne de la matrice, changée de signe.
///
/// `getOrientation`, utilisé par `precise_compass`, donne au contraire le cap
/// de l'axe y : vertical quand on tient le téléphone debout pour une photo.
CameraAxis cameraAxisFromRotationMatrix(List<double> matrix) {
  if (matrix.length != 9) {
    throw ArgumentError.value(matrix, 'matrix', '9 valeurs attendues');
  }
  return (east: -matrix[2], north: -matrix[5], up: -matrix[8]);
}

/// Azimut magnétique (0–360°) de la direction horizontale de [axis], ou null
/// si la caméra vise presque à la verticale.
double? cameraAzimuthDegrees(CameraAxis axis) {
  final horizontal = math.sqrt(axis.east * axis.east + axis.north * axis.north);
  final norm = math.sqrt(horizontal * horizontal + axis.up * axis.up);
  if (norm < 1e-6 || horizontal / norm < minHorizontalAxisComponent) {
    return null;
  }
  return _normalize(math.atan2(axis.east, axis.north) * 180 / math.pi);
}

/// Azimut vrai de la caméra : son azimut magnétique plus la déclinaison
/// magnétique.
///
/// La déclinaison est l'écart entre cap vrai et cap magnétique donnés par
/// `precise_compass`. Ces caps visent un autre axe que la caméra, mais leur
/// écart ne dépend que du lieu. Null tant que le cap vrai manque.
double? cameraTrueAzimuthDegrees({
  required CameraAxis axis,
  required double? headingMagnetic,
  required double? headingTrue,
}) {
  final magnetic = cameraAzimuthDegrees(axis);
  if (magnetic == null || headingMagnetic == null || headingTrue == null) {
    return null;
  }
  return _normalize(magnetic + headingTrue - headingMagnetic);
}

double _normalize(double degrees) {
  final normalized = degrees % 360;
  // `-0.0 % 360` vaut -0.0, et un résultat proche de 360 s'affiche « 360° ».
  return normalized >= 360 - 1e-9 || normalized == 0 ? 0 : normalized;
}
