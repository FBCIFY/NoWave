import 'dart:convert';

import '../../../core/location/coordinate_formatter.dart';
import '../../reports/domain/manual_report.dart';

/// Historique serveur, indépendant du push. Aucun état lu/non lu.
class Alert {
  const Alert({
    required this.id,
    required this.reportId,
    required this.version,
    required this.category,
    required this.longitude,
    required this.latitude,
    required this.distanceM,
    required this.alertedAt,
  });
  final String id;
  final String reportId;
  final int version;
  final ReportCategory category;
  final double longitude;
  final double latitude;
  final double distanceM;

  /// Toujours présent dans l’historique ; facultatif dans un push.
  final DateTime? alertedAt;

  String get eventKey => '$reportId:$version';
  String get positionDms =>
      '${formatDms(latitude, isLatitude: true)} · ${formatDms(longitude, isLatitude: false)}';

  factory Alert.fromJson(
    Map<String, dynamic> json, {
    bool requireAlertedAt = true,
  }) {
    final position = json['position'];
    if (position is! Map || position['type'] != 'Point') {
      throw const FormatException('Position d’alerte invalide.');
    }
    final coordinates = position['coordinates'];
    if (coordinates is! List || coordinates.length != 2) {
      throw const FormatException('Coordonnées d’alerte invalides.');
    }
    final longitude = finiteNumber(coordinates[0]);
    final latitude = finiteNumber(coordinates[1]);
    final distance = finiteNumber(json['distance_m']);
    final version = json['report_version'];
    if (longitude.abs() > 180 ||
        latitude.abs() > 90 ||
        distance < 0 ||
        version is! int ||
        version < 1) {
      throw const FormatException('Valeurs d’alerte invalides.');
    }
    return Alert(
      id: nonEmpty(json['id']),
      reportId: nonEmpty(json['report_id']),
      version: version,
      category: ReportCategory.values.firstWhere(
        (c) => c.apiValue == json['category'],
        orElse: () =>
            throw const FormatException('Catégorie d’alerte inconnue.'),
      ),
      longitude: longitude,
      latitude: latitude,
      distanceM: distance,
      alertedAt: !requireAlertedAt && json['alerted_at'] == null
          ? null
          : DateTime.parse(nonEmpty(json['alerted_at'])),
    );
  }

  static String nonEmpty(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Identifiant ou date absent.');
    }
    return value;
  }

  static double finiteNumber(Object? value) {
    if (value is! num || !value.isFinite) {
      throw const FormatException('Nombre invalide.');
    }
    return value.toDouble();
  }
}

class AlertPage {
  const AlertPage({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    required this.pages,
  });
  final List<Alert> items;
  final int page;
  final int limit;
  final int total;
  final int pages;

  factory AlertPage.fromJson(Map<String, dynamic> json) {
    final page = json['page'];
    final limit = json['limit'];
    final total = json['total'];
    final pages = json['pages'];
    final items = json['items'];
    if (page is! int ||
        page < 1 ||
        limit is! int ||
        limit < 1 ||
        total is! int ||
        total < 0 ||
        pages is! int ||
        pages < 0 ||
        items is! List ||
        items.length > limit ||
        (pages > 0 && page > pages)) {
      throw const FormatException('Pagination des alertes invalide.');
    }
    return AlertPage(
      items: [
        for (final item in items) Alert.fromJson(item as Map<String, dynamic>),
      ],
      page: page,
      limit: limit,
      total: total,
      pages: pages,
    );
  }
}

/// Contrat de data FCM proposé en attendant le worker : toutes les valeurs
/// FCM sont des chaînes ; position_dms est requis, position GeoJSON facultatif.
class AlertPush {
  const AlertPush({
    required this.alert,
    required this.expiresAt,
    this.messageId,
    required this.positionDms,
    this.recipientFirebaseUid,
  });
  final Alert alert;
  final DateTime expiresAt;
  final String? messageId;
  final String positionDms;
  final String? recipientFirebaseUid;

  bool expired(DateTime now) => !expiresAt.isAfter(now);

  factory AlertPush.fromData(Map<String, dynamic> data, {String? messageId}) {
    final expiresAt = DateTime.parse(Alert.nonEmpty(data['expires_at']));
    final positionDms = Alert.nonEmpty(data['position_dms']);
    final coordinates = _parseDms(positionDms);
    final alert = Alert.fromJson({
      'id': data['alert_id'],
      'report_id': data['report_id'],
      'report_version': int.parse(Alert.nonEmpty(data['report_version'])),
      'category': data['category'],
      'position': data.containsKey('position')
          ? jsonDecode(Alert.nonEmpty(data['position']))
          : {
              'type': 'Point',
              'coordinates': [coordinates.longitude, coordinates.latitude],
            },
      'distance_m': double.parse(Alert.nonEmpty(data['distance_m'])),
      'alerted_at': data['alerted_at'],
    }, requireAlertedAt: false);
    // Le GeoJSON fourni conserve sa précision, après contrôle de cohérence.
    const tolerance = 0.5 / 3600 + 1e-10;
    if ((coordinates.latitude - alert.latitude).abs() > tolerance ||
        (coordinates.longitude - alert.longitude).abs() > tolerance) {
      throw const FormatException('Position DMS incohérente avec le GeoJSON.');
    }
    return AlertPush(
      alert: alert,
      expiresAt: expiresAt,
      messageId: messageId,
      positionDms: positionDms,
      recipientFirebaseUid: data.containsKey('recipient_firebase_uid')
          ? Alert.nonEmpty(data['recipient_firebase_uid'])
          : null,
    );
  }

  /// DMS requis : latitude puis longitude, séparées par un point médian
  /// ou une virgule. Accepte les primes Unicode et les quotes ASCII.
  /// Les coordonnées dérivées servent aussi lorsque le GeoJSON est absent.
  static ({double latitude, double longitude}) _parseDms(String value) {
    const component =
        r"""(\d{1,3})°\s*(\d{1,2})[′']\s*(\d{1,2}(?:\.\d+)?)[″"]\s*""";
    final match = RegExp(
      '^\\s*$component([NS])\\s*[·,]\\s*$component([EW])\\s*\$',
    ).firstMatch(value);
    if (match == null) {
      throw const FormatException('Position DMS invalide.');
    }
    double coordinate(int offset, int maximum) {
      final degrees = int.parse(match.group(offset)!);
      final minutes = int.parse(match.group(offset + 1)!);
      final seconds = double.parse(match.group(offset + 2)!);
      final direction = match.group(offset + 3)!;
      if (degrees > maximum ||
          minutes >= 60 ||
          seconds >= 60 ||
          (degrees == maximum && (minutes != 0 || seconds != 0))) {
        throw const FormatException('Coordonnée DMS invalide.');
      }
      final absolute = degrees + minutes / 60 + seconds / 3600;
      return direction == 'S' || direction == 'W' ? -absolute : absolute;
    }

    return (latitude: coordinate(1, 90), longitude: coordinate(5, 180));
  }
}
