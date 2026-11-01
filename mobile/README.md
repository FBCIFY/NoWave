# Mobile

Client Flutter Android/iOS pour la carte, les signalements et les alertes.

## Prérequis

- Flutter 3.47.5.
- Un émulateur ou un téléphone configuré, et un backend NoWave accessible.

## Lancer

Depuis `mobile/`, créer la configuration locale :

```sh
test -f .env.json || cp .env.example.json .env.json
```

Compléter `.env.json` :

- `MAPBOX_ACCESS_TOKEN` : jeton public Mapbox.
- `API_BASE_URL` : backend, par exemple `https://api.no-wave.fr/`.
- `MARINE_API_BASE_URL` : backend marin facultatif ; vide, reprend l’API principale.

API locale sur le port 8000 : `http://10.0.2.2:8000/` sur émulateur Android,
`http://127.0.0.1:8000/` sur simulateur iOS.
Sur téléphone, utiliser l’API distante ou, en USB Android, lancer
`adb reverse tcp:8000 tcp:8000` et utiliser `http://127.0.0.1:8000/`.

```sh
flutter pub get --enforce-lockfile
flutter devices
flutter run --dart-define-from-file=.env.json
```

Flutter propose le choix de l’appareil si plusieurs sont disponibles. Garder `.env.json` hors Git ;
reconstruire et relancer l’app après un changement de configuration.

## Tests

Depuis `mobile/`, après `flutter pub get` :

```sh
flutter test --no-pub
```

Caméra, GPS, notifications et reprise en arrière-plan se vérifient sur téléphone réel.
