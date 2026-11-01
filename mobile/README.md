# NoWave mobile

Client Flutter Android/iOS. Prérequis : Flutter 3.47.5 et un émulateur ou téléphone configuré.

## Lancer

Depuis `mobile/`, créer le fichier local :

```sh
test -f .env.json || cp .env.example.json .env.json
```

Compléter `.env.json` :

- `MAPBOX_ACCESS_TOKEN` : jeton public Mapbox.
- `API_BASE_URL` : backend NoWave, par exemple `https://api.no-wave.fr/`.
- `MARINE_API_BASE_URL` : backend marin facultatif ; vide, reprend `API_BASE_URL`.

```sh
flutter pub get --enforce-lockfile
flutter devices
flutter run -d <device-id> --dart-define-from-file=.env.json
```

Remplacer `<device-id>` par l’identifiant affiché par `flutter devices`.
Les configurations Firebase sont versionnées. Garder `.env.json` et les clés
privées hors de Git ; reconstruire et redémarrer après un changement de configuration.

Backend local : `http://10.0.2.2:8000/` sur émulateur Android et
`http://127.0.0.1:8000/` sur simulateur iOS.
Sur téléphone, utiliser l’API distante. En USB Android, `adb reverse tcp:8000 tcp:8000`
permet aussi de joindre l’API locale à `http://127.0.0.1:8000/`.

## Compiler

Depuis `mobile/` :

```sh
flutter build apk --debug --dart-define-from-file=.env.json
```

L’APK debug sert aux essais. Une livraison Android ou iOS demande la signature
de la plateforme. Vérifier caméra, GPS, notifications et reprise en arrière-plan
sur téléphone réel ; le simulateur iOS ne valide pas les notifications distantes.
