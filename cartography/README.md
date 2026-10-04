# Fond marin NoWave — POC jour

POC Flutter autonome dans `../map_poc`, MapLibre sans clé API, sans Firebase
et sans backend métier. Il sert à choisir et tester le style. L'app métier
`../mobile` reste sur son moteur actuel ; migrer son écran complet ferait
intervenir GPS, cap, photo et signalements, hors du périmètre demandé.

Le **relief terrestre est réel, fourni par Mapzen/Tilezen sur AWS Open Data**.
L'île, la côte, la bathymétrie et les objets nautiques de la scène à 0°/0°
restent fictifs. La passe graphique affine désormais la scène de démonstration. Le bandeau distingue ces sources explicitement.
Le faux relief terrestre a été retiré. La scène fictive se trouve réellement
au milieu de l'océan : son île reste plate pour ne pas présenter un relief
sous-marin réel comme un relief terrestre. Un aperçu réel Marseille–Cassis
permet d'évaluer le hillshade terrestre.

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

Prérequis : Flutter 3.47+ / Dart 3.13+, Python 3.10+, accès réseau local et Internet pour le DEM.
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
Le chargement actif reste `MapLibreJsSource.cdn()` (MapLibre GL JS 6.4.1 sur unpkg).
Les fichiers présents dans `web/vendor/maplibre` ne sont pas utilisés par ce chargement.

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

`style.json` est un style v8 produit par `tools/build_style.py`, avec 61 couches dans la scène de démo.
Interpolations de zoom sur opacité, tailles, largeurs et textes. Palette exacte
et interpolation linéaire des profondeurs dans le générateur raster ; les pixels
sont rééchantillonnés linéairement. Terre beige, textures légères, catégories de
ports, balisage, réserves, chenaux, ouvrages et toponymie séparés.

`server.py` ne nécessite aucune dépendance Python externe à l'exécution.
Démo : GeoJSON et bathymétrie locaux, source DEM réelle externe explicitement
identifiée. Données réelles complètes : MBTiles vectoriel normalisé et raster
bathymétrique, DEM terrestre optionnel avec attribution dédiée. Lire [DATA_CONTRACT.md](DATA_CONTRACT.md).

Régénérer les assets :

```bash
python3 -m venv cartography/.venv
cartography/.venv/bin/pip install -r cartography/requirements-cassis.txt
cartography/.venv/bin/python cartography/tools/generate_demo.py
# Optionnel : recalculer le masque réel de diagnostic (25 tuiles DEM, Internet).
cartography/.venv/bin/python cartography/tools/prepare_relief_masks.py
python3 cartography/tools/build_style.py
```

Tests :

```bash
cartography/.venv/bin/python -m unittest discover -s cartography/tests -v
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
Outillage de génération : Pillow 12.3.0 et NumPy 2.5.3 (calcul des profondeurs par tableaux). Validation :
`@maplibre/maplibre-gl-style-spec 26.4.4`, Playwright 1.63.0 pour le test Web.
Verrous versionnés.
Sources techniques : [SDK Flutter officiel](https://pub.dev/packages/maplibre_gl),
[spécification MapLibre](https://maplibre.org/maplibre-style-spec/layers/).

## Limites

- La scène DEMO reste fictive. Le pilote Cassis fournit désormais des données
  OSM et SHOM séparées ; il ne constitue pas une carte de navigation officielle.
- La démo couvre 0,6° × 0,6° ; au-delà le fond reste bleu profond et les
  objets sont absents. Raster 2048 px, donc détails synthétiques limités à fort zoom.
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

## Validation initiale du POC (avant remplacement du relief)

- Flutter 3.47.6 / Dart 3.13.5 : `pub get`, analyse sans erreur et 4 tests du POC réussis.
- App métier : `pub get`, analyse sans erreur et 95 tests réussis.
- Serveur : 3 tests réussis (provenance, XYZ/TMS/gzip, séparation des sources et chemins).
- Styles démo et vectoriel+DEM : validation MapLibre v8 réussie (54 couches).
- Build Web réussi. Chromium, viewport 430×900 à densité 2 : rendu aux zooms
  10,5 / 14 / 16, déplacement par glisser et zoom par molette vérifiés,
  aucune erreur JS/MapLibre ni requête externe à cette étape initiale.
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

## Relief Mapzen Terrain Tiles / AWS Open Data

Source : [Terrain Tiles sur AWS Open Data](https://registry.opendata.aws/terrain-tiles/).
URL utilisée, sans authentification :

```text
https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png
```

MapLibre : `type=raster-dem`, `tileSize=256`, `encoding=terrarium`, `maxzoom=15`.
Décodage en mètres : `R × 256 + G + B / 256 − 32768`.
**Aucune clé API ni aucun compte AWS n'est nécessaire.** Le navigateur ou le
SDK natif charge ces tuiles depuis Internet pendant le test. Les assets métier
restent locaux. MapLibre Web est chargé par le CDN actuel. Le mode totalement hors ligne
n'est plus disponible tant que le DEM et le chargement Web ne sont pas auto-hébergés ou mis en cache.
Une connexion Internet absente peut laisser le relief indisponible ; la démo
bathymétrique locale reste indépendante.

### Attribution

La source `relief.attribution` crédite Mapzen/Tilezen, AWS Open Data,
EU-DEM/Copernicus, USGS et NOAA, avec un lien vers
[les notices complètes des producteurs](assets/mapzen-attribution.html).
Ces notices incluent également ArcticDEM, Geoscience Australia, Austria DGM,
Canada, INEGI, LINZ, Kartverket et Environment Agency pour les zones concernées.
Elles proviennent des [exigences Tilezen/Joerd](https://github.com/tilezen/joerd/blob/master/docs/attribution.md).
Le registre AWS renvoie à ces exigences ; « AWS » seul n'est pas une attribution
suffisante. Accès au jeu Terrain Tiles le 3 octobre 2026.

La réponse HTTP d'une tuile Cassis testée porte
`x-amz-meta-x-imagery-sources: eudem/eudem_dem_5deg_n40e005.tif`.
Ce résultat concerne cette tuile ; le dataset mondial combine plusieurs sources.

### Hillshade et protection de la mer

Couche native `hillshade` ; aucune extrusion ni terrain 3D. Exagération :
0 à z7, 0,15 à z10, 0,20 à z14, 0,22 à z18. Ombres gris/beige, contraste
faible, palette terrestre préservée (dont le passage #F1EFE9 vers #E5E2D9).

Le DEM contient aussi du relief sous-marin et des coutures de tuiles. Dans la
scène fictive, un masque RGBA restitue exactement les couleurs du raster
bathymétrique original au-dessus du hillshade. L'extérieur de la couverture
est recouvert de la couleur marine d'origine. Les courbes et objets restent
au-dessus du masque. Le remplissage opaque de l'île fictive couvre le DEM marin,
car cette île n'existe pas dans la géographie réelle.

Dans l'aperçu réel, le masque d'eau est préparé depuis 25 tuiles Mapzen à z12
(eau : altitude ≤ 0 m). Une fermeture morphologique de 3 pixels élimine des
anneaux côtiers dus au rééchantillonnage. Ce masque de diagnostic est local,
limité à Marseille–Cassis, et **n'est pas un littoral officiel**. Il ne modifie
pas les altitudes Mapzen. Une production devra utiliser un vrai masque marin
aligné sur son littoral, en particulier pour les terres sous le niveau de la mer.

### Test réel Marseille / Cassis

Remplacer le serveur de démo par :

```bash
python3 cartography/server.py --host 0.0.0.0 --relief-preview \
  --center 5.53 43.205 --zoom 12
```

Puis lancer le POC avec la même commande Flutter et la même URL `style.json`.
Pour Marseille : `--center 5.37 43.30 --zoom 12`.
L'aperçu conserve la source et les propriétés du hillshade, mais n'affiche
pas la bathymétrie ou les objets de la démo à des coordonnées réelles.
La mer y est une couleur unie, **sans signification de profondeur** ; la légende
bathymétrique est masquée. La couverture du masque est publiée dans
`assets/mapzen-preview-sea-mask.json`. Hors de cette emprise, la mer reste unie.

### Remplacement ultérieur du DEM

La source de vérité reste `tools/build_style.py`, fonction `relief_source`.
Changer la source ne nécessite pas de réécrire les propriétés visuelles :

```bash
python3 cartography/server.py --relief-preview \
  --relief-tiles 'http://localhost:8080/dem/{z}/{x}/{y}.png' \
  --relief-attribution 'Producteur, licence, date du DEM fourni'
```

GLO-90 ou SRTM devront être convertis en tuiles XYZ Terrarium 256 px (ou prévoir
un autre encodage dans la seule configuration source). Le masque d'eau de
l'aperçu reste dérivé de Mapzen ; le remplacer aussi si le littoral/DEM change.
En mode MBTiles complet, l'ancien contrat de DEM masqué aux terres reste requis.
Le dossier non suivi `data/glo90/` préexistant n'a pas été modifié.

### Validation du remplacement

Génération et validation des styles démo, vectoriel+DEM et aperçu réel réussies.
Tests serveur/masques : 7 réussis. Flutter : analyse sans erreur et 6 tests réussis.
Build Web réussi. Chromium : tuiles AWS reçues en HTTP 200, aucun message d'erreur
JS/MapLibre, gestes de déplacement et zoom vérifiés dans la démo.
Captures avant/après de Marseille et Cassis : « avant » = même aperçu sans
hillshade, « après » = hillshade Mapzen actif. Les anciennes captures de la scène
fictive restent disponibles pour comparaison avec le POC précédent.

Test automatisé du relief (démo sur 8765, aperçu réel sur 8767, Web sur 8766) :

```bash
python3 cartography/server.py --port 8767 --relief-preview
# Autre terminal, avec les deux autres serveurs déjà actifs :
npm run test:relief --prefix cartography
```

Les résultats détaillés et captures vont dans `test-results/mapzen`.
Pour le contrôle pixel avec Pillow, définir `NOWAVE_PYTHON` si le Python par
défaut ne possède pas Pillow, par exemple :

```bash
NOWAVE_PYTHON="$PWD/cartography/.venv/bin/python" npm run test:relief --prefix cartography
```

Captures conservées pour revue : [index avant/après](previews/mapzen/README.md),
[Cassis avant](previews/mapzen/cassis-before.png), [Cassis après](previews/mapzen/cassis-after.png),
[Marseille avant](previews/mapzen/marseille-before.png), [Marseille après](previews/mapzen/marseille-after.png),
[démo après](previews/mapzen/demo-after.png). Contrôle pixel : 288 332 pixels marins
opaques comparés, aucun changé par l'activation du hillshade.
Android/iOS physiques non exécutés dans cet environnement. Aucun commit ni push
créé pendant cette modification, en attente de revue du résultat.


## Passe graphique vers la référence

Référence inspectée : `reference/nowave-target.png.png` (double extension du fichier fourni).
Les six captures, leurs positions reproductibles et la comparaison détaillée sont
présentées dans [VISUAL_REVIEW.md](VISUAL_REVIEW.md). Cette passe ne certifie pas une carte de navigation.

Le générateur de démo produit un champ de profondeur continu avec hauts-fonds,
îlots et courbes issues du même modèle synthétique. Lissage limité des courbes
puis simplification à environ 3 m, GeoJSON inférieur à 1 Mo. Le raster de 2048 px
couvre 0,6° (environ 33 m/pixel à l'équateur). Le masque marin fictif est régénéré
avec ces assets ; aucune nouvelle source géographique n'est utilisée.
Les bassins, pontons à doigts, digues et feux d'entrée restent **DEMO**.
Le parc éolien possède uniquement un contour, sans remplissage ni turbines.

Les captures globales/régionales utilisent z10,8/z12 pour cette petite île fictive.
La hiérarchie du style reste définie sur z4–18 : à z4–6 la scène est trop petite
pour valider une composition continentale comme la référence.
Le littoral réel du diagnostic DEM reste approximatif et doit être remplacé.
Cassis, Marseille et La Ciotat vérifient uniquement le relief et le contraste terre/mer :
leur bathymétrie, leurs infrastructures et leurs objets nautiques réels sont **MISSING**.

Avec les serveurs démo 8765 et Web 8766 actifs :

```bash
npm run test:visual --prefix cartography
```

Le test observe l'instance créée par Flutter après son chargement CDN, sans injecter
une bibliothèque locale. Il contrôle les couches visibles des six scènes, les erreurs,
les réponses DEM et les gestes pan/zoom. `browser-result.json` conserve les résultats.

## Port pilote Cassis réel

Le scénario supplémentaire `CASSIS_REAL` reprend le style validé avec un littoral
vectoriel et des objets OSM, une bathymétrie SHOM et le relief Mapzen inchangé.
Lancement : `python3 cartography/server.py --real-cassis`. Les sources DEMO et
leurs six captures restent disponibles. Voir [préparation, licences et limites](CASSIS_REAL.md).
**Ne pas utiliser NoWave pour la navigation officielle.**

## Pipeline régional générique (France Méditerranée)

Le point d’entrée est désormais `tools/prepare_region.py --region <id>`.
Il conserve la recette Cassis et fournit une ingestion PBF locale, une mosaïque
SHOM multi-source par blocs, des courbes issues du même champ et des PNG XYZ
reprenables. Les produits réels doivent être déclarés avec leurs métadonnées,
emprises et SHA256 ; aucune profondeur inconnue n’est remplacée par zéro.

Voir **[FRANCE_MED_REAL.md](FRANCE_MED_REAL.md)** pour les entrées nécessaires,
les commandes exactes, projections, cache, licences et limites. Les deux modèles
`regions/france_med.*.example.json` sont volontairement incomplets : ils ne
prétendent pas représenter des données déjà acquises.

```bash
python3 cartography/server.py --region cassis
# Après préparation et construction des tuiles régionales :
python3 cartography/server.py --region france_med
```

Les routes résolvent l’identifiant de région sans duplication. Le profil MapLibre
réutilise les règles Cassis, la palette et l’interpolation linéaire. Flutter
accepte `REGION_REAL` en conservant le plein écran et sans ajout de GPS.
MBTiles et sorties régionales volumineuses restent ignorés par Git.
**NoWave n’est pas une carte officielle de navigation.**
