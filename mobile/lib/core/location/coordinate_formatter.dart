/// Formate une coordonnée en degrés, minutes, secondes (ex. `48° 23′ 12″ N`).
String formatDms(double value, {required bool isLatitude}) {
  final totalSeconds = (value.abs() * 3600).round();

  final degrees = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  final direction = isLatitude
      ? (value < 0 ? 'S' : 'N')
      : (value < 0 ? 'W' : 'E');

  return '$degrees° $minutes′ $seconds″ $direction';
}
