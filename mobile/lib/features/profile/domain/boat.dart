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

/// Bateau personnel. Les champs facultatifs peuvent être effacés via null.
class Boat {
  const Boat({
    required this.id,
    required this.type,
    this.name,
    this.flagCountry,
  });
  final String id;
  final BoatType type;
  final String? name;
  final String? flagCountry;

  factory Boat.fromJson(Map<String, dynamic> json) => Boat(
    id: json['id'] as String,
    type: BoatType.values.firstWhere(
      (type) => type.apiValue == json['boat_type'],
      orElse: () => throw const FormatException('Type de bateau inconnu.'),
    ),
    name: json['name'] as String?,
    flagCountry: json['flag_country'] as String?,
  );
}
