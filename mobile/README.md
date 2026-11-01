# App mobile

Flutter 3.47.5, avec un émulateur ou un téléphone configuré. Les commandes se lancent dans `mobile/`.

Commencer par le fichier de configuration local :

```sh
test -f .env.json || cp .env.example.json .env.json
```

Dans `.env.json`, mettre le jeton public Mapbox dans `MAPBOX_ACCESS_TOKEN` et l’adresse du backend dans `API_BASE_URL`, par exemple `https://api.no-wave.fr/`.
Laisser `MARINE_API_BASE_URL` vide pour charger aussi les données marines depuis ce backend.

Pour joindre l’API locale sur le port 8000, utiliser `http://10.0.2.2:8000/` sur l’émulateur Android, `http://127.0.0.1:8000/` sur le simulateur iOS.
Sur téléphone, utiliser l’API distante. En USB Android, cette commande permet de garder l’API locale :

```sh
adb reverse tcp:8000 tcp:8000
```

Renseigner alors `http://127.0.0.1:8000/` dans `API_BASE_URL`.

```sh
flutter pub get --enforce-lockfile
flutter devices
flutter run --dart-define-from-file=.env.json
```

Flutter propose le choix de l’appareil si plusieurs sont disponibles. Garder `.env.json` hors Git et reconstruire l’app après un changement de configuration.

Pour lancer les tests, toujours dans `mobile/` :

```sh
flutter test --no-pub
```

Caméra, GPS, notifications et reprise en arrière-plan se vérifient sur téléphone réel.
