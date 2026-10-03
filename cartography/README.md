# Fond marin NoWave — POC jour

POC Flutter autonome dans `../map_poc`, MapLibre sans clé API, sans Firebase
et sans backend métier. Il sert à choisir et tester le style. L'app métier
`../mobile` reste sur son moteur actuel ; migrer son écran complet ferait
intervenir GPS, cap, photo et signalements, hors du périmètre demandé.

**Démo intégralement fictive**, île autour de 0°/0°. Le bandeau est permanent,
chaque objet porte `demo=true`, les noms indiquent « démo » ou « fictive ».
Le relief, les profondeurs, courbes, secteurs et autorisations de mouillage
ne sont pas des données nautiques réelles.

## Audit initial

- Branche `feat/NW-map-style`, dépôt initialement propre ; aucun `AGENTS.md` applicable.
- App : `mobile/pubspec.yaml`, Flutter/Dart, Mapbox `^2.30.1`.
- Démarrage : `mobile/lib/main.dart` initialise Firebase et Mapbox.
- Configuration : `mobile/lib/core/map/map_config.dart`, Mapbox Standard.
- Écran : `mobile/lib/features/map/presentation/map_screen.dart`, GPS/Geolocator,
  cap/precise_compass, signalements et photo, composants de marqueurs et bannière.
- Assets préexistants : polices Raleway et puck GLB ; aucune bathymétrie.
- MapTiler : ancienne variable documentée, pas utilisée par l'app ; aucun MapLibre
  ou flutter_map avant ce POC.
- Réseau métier : `mobile/lib/core/api/api_service.dart`. Tuiles backend :
  `backend/app/api/routes/map_tiles.py`, tuiles MVT de signalements, pas un fond nautique.
- Tests carte existants : marqueurs et bannière ; aucun test du style nautique.

## Lancement par Vadim

Prérequis : Flutter 3.47+ / Dart 3.13+, Python 3.10+, accès réseau local.
Android : JDK 21 et SDK Android. iOS : macOS/Xcode, cible générée iOS 15+.
Web : navigateur avec WebGL2. Le POC a son propre identifiant d'application.

Terminal 1, depuis la racine du dépôt :

```bash
python3 cartography/server.py --host 0.0.0.0
```

Alternative serveur :

```bash
docker compose -f cartography/compose.yaml up --build
```

Terminal 2 :

```bash
cd map_poc
flutter pub get
flutter devices
flutter run -d chrome --dart-define=NOWAVE_STYLE_URL=http://127.0.0.1:8765/style.json
```

Android Emulator :

```bash
flutter run -d <identifiant-emulateur> --dart-define=NOWAVE_STYLE_URL=http://10.0.2.2:8765/style.json
```

Simulateur iOS :

```bash
flutter run -d <identifiant-simulateur> --dart-define=NOWAVE_STYLE_URL=http://127.0.0.1:8765/style.json
```

Téléphone physique : même réseau que le poste, port 8765 accessible. Remplacer
l'adresse d'exemple par l'IP du poste :

```bash
flutter run -d <identifiant-telephone> --dart-define=NOWAVE_STYLE_URL=http://192.168.1.10:8765/style.json
```

Le serveur construit les liens d'assets depuis le Host demandé par le client.
Derrière un proxy, passer `--public-url http://adresse-accessible:8765`.
Après changement de `NOWAVE_STYLE_URL`, redémarrer complètement Flutter.
L'HTTP local est autorisé dans ce projet de POC Android/iOS uniquement.

Sans Chrome installé, vérifier le build Web puis le servir :

```bash
cd map_poc
flutter build web --no-web-resources-cdn
python3 -m http.server 8766 --directory build/web
```

Ouvrir http://localhost:8766 ; garder le serveur cartographique actif.
Les modules MapLibre GL JS 6.4.1 sont embarqués dans `web/vendor/maplibre`.

## Parcours visuel

Déplacer au doigt et pincer pour zoomer ; Web : glisser et molette/double-clic.
Le zoom courant est affiché en haut. Aucun bouton GPS/cap/signalement.

| Zoom | À observer |
|---|---|
| 6–9 | mer dominante, terre sobre, toponymie peu chargée |
| 10–12 | dégradé continu, courbes fines, côtes et îlots, premières icônes |
| 13–14 | côte est de l'île : cinq catégories de ports, noms progressifs, zones discrètes |
| 15–16 | côte est : feux, secteurs fictifs, formes/cardinales des bouées, pontons |
| 17–18 | identifiants lumineux, noms d'épave/récifs et détails secondaires |

Pour approcher les objets : viser la côte est, longitude 0,044°, latitude
−0,003° (port), puis 0,049°/−0,016° (balises). Récifs et hauts-fonds au nord-est.
Dézoomer lentement et vérifier la disparition progressive, l'absence de
saturation, la lisibilité des labels blancs et les contours de côte.
Les valeurs des longues courbes sont répétées via `symbol-placement=line`
et `symbol-spacing=240`. Les rares courbes profondes sont moins nombreuses
que les courbes côtières ; toutes partagent le même tracé visuel.

## Architecture et évolution

`style.json` est un style v8 produit par `tools/build_style.py`, avec 54 couches.
Interpolations de zoom sur opacité, tailles, largeurs et textes. Palette exacte
et interpolation linéaire des profondeurs dans le générateur raster ; les pixels
sont rééchantillonnés linéairement. Terre beige, textures légères, catégories de
ports, balisage, réserves, chenaux, ouvrages et toponymie séparés.

`server.py` ne nécessite aucune dépendance Python externe à l'exécution.
Démo : GeoJSON et images locales. Données réelles : MBTiles vectoriel normalisé
et raster bathymétrique, DEM terrestre optionnel. Aucun mélange automatique des
sources fictives et réelles. Lire [DATA_CONTRACT.md](DATA_CONTRACT.md).

Régénérer les assets :

```bash
python3 -m venv cartography/.venv
cartography/.venv/bin/pip install -r cartography/requirements.txt
cartography/.venv/bin/python cartography/tools/generate_demo.py
python3 cartography/tools/build_style.py
```

Tests :

```bash
python3 -m unittest discover -s cartography/tests -v
npm ci --prefix cartography
npm test --prefix cartography
cd map_poc
flutter pub get
flutter analyze
flutter test
flutter build web --no-web-resources-cdn
cd ..
git diff --check
git status -sb
```

Dépendances POC : `maplibre_gl 0.27.1`, `http ^1.6.0`, `flutter_lints ^6.0.0`.
Outillage de génération : Pillow 12.3.0. Validation :
`@maplibre/maplibre-gl-style-spec 26.4.4`, Playwright 1.63.0 pour le test Web.
Verrous versionnés.
Sources techniques : [SDK Flutter officiel](https://pub.dev/packages/maplibre_gl),
[spécification MapLibre](https://maplibre.org/maplibre-style-spec/layers/).

## Limites

- Aucune bathymétrie, côte ou aide à la navigation réelle livrée ; la scène
  permet l'évaluation du style uniquement. Pas encore d'importeur GEBCO/OSM/ENC.
- La démo couvre 0,6° × 0,6° ; au-delà le fond reste bleu profond et les
  objets sont absents. Raster 1536 px, donc détails synthétiques limités à fort zoom.
- Sources réelles à acquérir/normaliser et licences à vérifier. Le contrat
  n'est pas compatible directement avec un schéma OpenMapTiles sans adaptateur.
- Les grandes zones maritimes sont des labels horizontaux dans ce POC.
  Un label qui suit la géographie requerra une géométrie dédiée.
- Catalogue de sprites simplifié ; compléter si une forme/couleur réelle
  n'est pas représentée. Ne pas substituer silencieusement un symbole inexact.
- Les données réelles de secteurs, estran, récifs et zones restent absentes
  tant qu'aucune source vérifiée n'est fournie.
- Le chargement du style a un délai et un bouton de reprise. Une erreur de
  tuile individuelle après chargement relève aussi des logs MapLibre/serveur.
- Build et rendu Web vérifiables ici ; essais Android/iOS physiques à faire
  par Vadim. Ce POC n'effectue pas la migration de l'app métier.

## Validation effectuée le 3 octobre 2026

- Flutter 3.47.6 / Dart 3.13.5 : `pub get`, analyse sans erreur et 4 tests du POC réussis.
- App métier : `pub get`, analyse sans erreur et 95 tests réussis.
- Serveur : 3 tests réussis (provenance, XYZ/TMS/gzip, séparation des sources et chemins).
- Styles démo et vectoriel+DEM : validation MapLibre v8 réussie (54 couches).
- Build Web réussi. Chromium, viewport 430×900 à densité 2 : rendu aux zooms
  10,5 / 14 / 16, déplacement par glisser et zoom par molette vérifiés,
  aucune erreur JS/MapLibre ni requête externe.
- Captures : [vue générale](previews/overview.png), [côte et port](previews/coast.png),
  [bouées](previews/buoys.png). Toutes les données visibles sont fictives.
- Docker non testé : intégration Docker Desktop indisponible dans ce WSL.
  Le serveur Python direct a été utilisé. Android/iOS non exécutés ici.

Test Web automatisé (après le build, serveurs actifs sur 8765 et 8766) :

```bash
cd cartography
npm ci
npx playwright install chromium
npm run test:web
```

Sous Linux minimal, installer aussi les bibliothèques système Chromium avec
`npx playwright install-deps chromium` si elles manquent. Le test vérifie
les symboles de bouées, le déplacement et le zoom, puis écrit des captures
dans `test-results/map-poc` (ignoré par Git).
