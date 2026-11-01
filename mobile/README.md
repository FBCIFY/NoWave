# NoWave mobile

App Flutter Android/iOS : carte, signalements et alertes.

## Lancer

Versions des outils et contrôles : [tests](../docs/TESTING.md).
Depuis `mobile/`, créer `.env.json`, compléter ses valeurs, puis lancer l’app :

```sh
cp .env.example.json .env.json
flutter pub get --enforce-lockfile
flutter devices
flutter run -d <device-id> --dart-define-from-file=.env.json
```

`<device-id>` vient de `flutter devices`. Les configurations Firebase sont
versionnées ; `.env.json` et les clés privées restent hors de Git.

## Configuration

| Variable de `.env.json` | Usage |
| --- | --- |
| `MAPBOX_ACCESS_TOKEN` | Jeton public Mapbox |
| `API_BASE_URL` | API principale, par exemple `https://api.no-wave.fr/` |
| `MARINE_API_BASE_URL` | API marine facultative ; vide, reprend l’API principale |

Backend local : `http://10.0.2.2:8000/` sur émulateur Android,
`http://127.0.0.1:8000/` sur simulateur iOS, adresse réseau du poste sur téléphone.
En USB Android, `adb reverse tcp:8000 tcp:8000` donne accès au même port local.
Après un changement de configuration, reconstruire et redémarrer l’app.

## Code

| Emplacement | Contenu |
| --- | --- |
| `lib/main.dart`, `lib/app/` | Initialisation et thème |
| `lib/core/` | API, GPS, appareils, notifications et capteurs |
| `lib/features/auth/`, `profile/` | Comptes et préférences |
| `lib/features/map/`, `home/`, `alerts/` | Carte et alertes |
| `lib/features/reports/`, `camera/` | Publication et photos |

## Compiler

Depuis `mobile/`, après installation des dépendances :

```sh
flutter build apk --debug --dart-define-from-file=.env.json
```

Ce build sert aux essais Android. Une livraison Android ou iOS demande la
configuration de signature de la plateforme.

Caméra, GPS, autorisations, notifications et reprise en arrière-plan se
vérifient sur téléphone réel. Une fermeture forcée interrompt le suivi GPS ;
les notifications distantes ne se valident pas avec le seul simulateur iOS.

Routes et règles métier : [Contrats API](../docs/API.md).
Chargement de la carte : [couches marines](../docs/architecture/marine-zoom-persistence.md).
