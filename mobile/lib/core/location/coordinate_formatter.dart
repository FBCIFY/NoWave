/// Formate une coordonnée en degrés, minutes, secondes (ex. `48° 23′ 12″ N`).
String formatDms(double value, {required bool isLatitude}) {
  final (:degrees, :minutes, :seconds, :direction) = _dms(
    value,
    isLatitude: isLatitude,
  );
  return '$degrees° $minutes′ $seconds″ $direction';
}

/// Variante serrée du compas, à largeur fixe : `48°23′02″N`, et la longitude
/// sur trois chiffres (`004°29′24″W`) comme sur les instruments marins.
String formatDmsCompact(double value, {required bool isLatitude}) {
  final (:degrees, :minutes, :seconds, :direction) = _dms(
    value,
    isLatitude: isLatitude,
  );
  String two(int part) => part.toString().padLeft(2, '0');
  final degreesText = degrees.toString().padLeft(isLatitude ? 2 : 3, '0');
  return '$degreesText°${two(minutes)}′${two(seconds)}″$direction';
}

({int degrees, int minutes, int seconds, String direction}) _dms(
  double value, {
  required bool isLatitude,
}) {
  final totalSeconds = (value.abs() * 3600).round();
  return (
    degrees: totalSeconds ~/ 3600,
    minutes: (totalSeconds % 3600) ~/ 60,
    seconds: totalSeconds % 60,
    direction: isLatitude ? (value < 0 ? 'S' : 'N') : (value < 0 ? 'W' : 'E'),
  );
}
