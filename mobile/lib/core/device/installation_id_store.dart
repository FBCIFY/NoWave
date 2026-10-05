import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Identifiant de cette installation de l'app (`installation_id` côté
/// backend), gardé sur le téléphone d'un lancement à l'autre.
///
/// Le backend lie cet identifiant au premier compte qui l'enregistre : il est
/// donc oublié à la déconnexion, et le compte suivant en reçoit un nouveau.
class InstallationIdStore {
  static const String _key = 'installation_id';

  final Future<SharedPreferences> Function() _preferences;
  final String Function() _newId;

  /// Lecture en cours ou terminée, partagée par les appels simultanés pour
  /// ne jamais créer deux identifiants.
  Future<String>? _current;

  InstallationIdStore({
    Future<SharedPreferences> Function()? preferences,
    String Function()? newId,
  }) : _preferences = preferences ?? SharedPreferences.getInstance,
       _newId = newId ?? const Uuid().v4;

  /// Renvoie l'identifiant actuel, ou en crée un au premier appel.
  Future<String> read() async {
    final pending = _current ??= _readOrCreate();
    try {
      return await pending;
    } catch (_) {
      // Lecture ratée : le prochain appel réessaie au lieu de garder l'erreur.
      if (identical(_current, pending)) _current = null;
      rethrow;
    }
  }

  /// Oublie l'identifiant : le prochain [read] en crée un nouveau.
  Future<void> reset() async {
    final pending = _current;
    _current = null;
    // Une lecture en cours pourrait réécrire l'ancien identifiant après nous.
    try {
      await pending;
    } catch (_) {}
    final preferences = await _preferences();
    await preferences.remove(_key);
  }

  Future<String> _readOrCreate() async {
    final preferences = await _preferences();
    final saved = preferences.getString(_key);
    if (saved != null && saved.isNotEmpty) return saved;

    final id = _newId();
    await preferences.setString(_key, id);
    return id;
  }
}
