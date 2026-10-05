import 'manual_report.dart';

/// Types de bateau ; [apiValue] est la valeur renvoyée par le backend.
enum BoatType {
  sailboat('voilier', 'Voilier'),
  motorboat('bateau_moteur', 'Bateau à moteur'),
  catamaran('catamaran', 'Catamaran'),
  rib('semi_rigide', 'Semi-rigide'),
  jetSki('jet_ski', 'Jet-ski'),
  other('autre', 'Autre');

  const BoatType(this.apiValue, this.label);

  final String apiValue;

  /// Libellé affiché dans la fiche.
  final String label;
}

/// État de la photo d'un signalement photo.
enum ReportPhotoStatus {
  pending('pending'),
  uploaded('uploaded'),
  failed('failed');

  const ReportPhotoStatus(this.apiValue);

  final String apiValue;
}

/// Auteur visible d'un signalement. [username] est `null` si l'auteur cache
/// son nom ; [deleted] indique un compte supprimé.
class ReportAuthor {
  const ReportAuthor({required this.username, required this.deleted});

  final String? username;
  final bool deleted;
}

/// Bateau de l'auteur, visible seulement s'il le partage.
class ReportBoat {
  const ReportBoat({required this.name, required this.type});

  final String? name;
  final BoatType type;
}

/// Photo d'un signalement. [url] reste `null` tant que le backend ne la
/// sert pas.
class ReportPhoto {
  const ReportPhoto({required this.status, required this.url});

  final ReportPhotoStatus status;
  final String? url;
}

/// Signalement actif renvoyé par `GET api/v1/reports/{id}`, pour la fiche
/// de détail. [ReportDetail.fromJson] lit les clés en snake_case et lève une
/// [FormatException] sur une catégorie, un bateau ou un état de photo
/// inconnu.
class ReportDetail {
  const ReportDetail({
    required this.id,
    required this.category,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.observedAt,
    required this.expiresAt,
    required this.author,
    required this.boat,
    required this.photo,
  });

  final String id;
  final ReportCategory category;
  final String? description;
  final double latitude;
  final double longitude;
  final DateTime observedAt;
  final DateTime expiresAt;

  /// `null` si l'auteur cache son nom.
  final ReportAuthor? author;

  /// `null` si l'auteur ne partage pas son bateau.
  final ReportBoat? boat;

  /// `null` pour un signalement manuel.
  final ReportPhoto? photo;

  factory ReportDetail.fromJson(Map<String, dynamic> json) {
    // GeoJSON : longitude puis latitude.
    final position = json['final_position'] as Map<String, dynamic>;
    final coordinates = position['coordinates'] as List<dynamic>;
    if (coordinates.length < 2) {
      throw const FormatException('Position du signalement invalide.');
    }
    final author = json['author'] as Map<String, dynamic>?;
    final boat = json['boat'] as Map<String, dynamic>?;
    final photo = json['photo'] as Map<String, dynamic>?;

    return ReportDetail(
      id: json['id'] as String,
      category: _byApiValue(
        ReportCategory.values,
        json['category'],
        (category) => category.apiValue,
      ),
      description: json['description'] as String?,
      latitude: (coordinates[1] as num).toDouble(),
      longitude: (coordinates[0] as num).toDouble(),
      observedAt: DateTime.parse(json['observed_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      author: author == null
          ? null
          : ReportAuthor(
              username: author['username'] as String?,
              deleted: author['deleted'] as bool,
            ),
      boat: boat == null
          ? null
          : ReportBoat(
              name: boat['name'] as String?,
              type: _byApiValue(
                BoatType.values,
                boat['boat_type'],
                (type) => type.apiValue,
              ),
            ),
      photo: photo == null
          ? null
          : ReportPhoto(
              status: _byApiValue(
                ReportPhotoStatus.values,
                photo['status'],
                (status) => status.apiValue,
              ),
              url: photo['url'] as String?,
            ),
    );
  }

  /// Valeur de [values] dont l'[apiValue] vaut [raw].
  static T _byApiValue<T>(
    List<T> values,
    Object? raw,
    String Function(T value) apiValue,
  ) {
    for (final value in values) {
      if (apiValue(value) == raw) return value;
    }
    throw FormatException('Valeur inconnue : $raw');
  }
}
