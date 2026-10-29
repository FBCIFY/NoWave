/// Mètres dans un mille nautique.
const _metersPerNauticalMile = 1852.0;

/// Huit directions, dans le sens des aiguilles d'une montre depuis le nord.
const _compassPoints = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];

/// Distance en milles nautiques : une décimale sous 10 NM (`2,4 NM`),
/// arrondie au-delà (`12 NM`).
String formatNauticalMiles(double meters) {
  final miles = meters / _metersPerNauticalMile;
  if (miles < 0.1) return '< 0,1 NM';
  final text = miles < 10
      ? miles.toStringAsFixed(1).replaceAll('.', ',')
      : miles.round().toString();
  return '$text NM';
}

/// Direction la plus proche d'un cap en degrés (0 = nord, 90 = est), qu'il
/// soit entre -180 et 180 ou entre 0 et 360.
String compassPoint(double bearing) {
  final degrees = bearing % 360;
  return _compassPoints[(degrees / 45).round() % _compassPoints.length];
}

/// Date en heure locale, à placer dans une phrase : « aujourd’hui à 11:30 »,
/// « hier à 11:30 », « demain à 11:30 » ou « le 03/10/2026 à 11:30 ».
String formatDayTime(DateTime date, {required DateTime now}) {
  final local = date.toLocal();
  final time = '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
  final dateDay = DateTime(local.year, local.month, local.day);
  final today = DateTime(now.year, now.month, now.day);
  // En heures arrondies : un changement d'heure ne décale pas le jour.
  final days = (dateDay.difference(today).inHours / 24).round();
  final day = switch (days) {
    0 => 'aujourd’hui',
    -1 => 'hier',
    1 => 'demain',
    _ => 'le ${_twoDigits(local.day)}/${_twoDigits(local.month)}/${local.year}',
  };
  return '$day à $time';
}

/// Nombre sur deux chiffres : `9` devient `09`.
String _twoDigits(int value) => value.toString().padLeft(2, '0');
