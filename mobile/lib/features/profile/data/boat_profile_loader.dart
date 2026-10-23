import '../domain/boat.dart';
import 'profile_service.dart';

/// Cache limité à une ouverture du profil, y compris l'absence de bateau.
class BoatProfileLoader {
  BoatProfileLoader(this._service);
  final ProfileService _service;
  Future<Boat?>? _pending;
  bool _loaded = false;
  Boat? _boat;

  bool get loaded => _loaded;
  Boat? get boat => _boat;

  Future<Boat?> load({bool refresh = false}) {
    // Un clic pendant le préchargement partage la requête en cours.
    if (_pending case final pending?) return pending;
    if (_loaded && !refresh) return Future.value(_boat);
    if (refresh) invalidate();
    return _pending = _service
        .getBoat()
        .then((boat) {
          update(boat);
          return boat;
        })
        .whenComplete(() => _pending = null);
  }

  void invalidate() {
    _boat = null;
    _loaded = false;
  }

  void update(Boat? boat) {
    _boat = boat;
    _loaded = true;
  }
}
