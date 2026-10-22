# NW-220 — Zones grises et pixellisation : audits et validations

## 1. Branche et SHA initial

Branche : `fix/NW-220-coastal-raster-artifacts`. Départ : `433c7bad`.
Mission locale du 22 octobre 2026 (Europe/Paris). Aucun commit/publication autorisé dans cette mission.

## 2. État Git et fichiers préexistants

État initial suivi propre, `git diff --check` réussi ; seuls `docs/design/` et `mobile/codex_photo/` sont non suivis. Inventaire SHA-256 des **sept** fichiers protégés enregistré avant travail. Le précédent rapport et ses preuves restent une validation historique de l'ancien choix de fond, désormais remplacé par la nouvelle règle produit.

## 3. Analyse de `fix_gris.jpg`

Fichier réellement ouvert. SHA-256 `204279e8736a0e2d1a02ddc2b0e59fe223d8de0623fd4e721e53e798b34b0df8`.
Observation : Z16.3 ; digue claire en diagonale, larges plages grises sur l'eau autour, eau turquoise de part et d'autre ; sondes et balisage présents. Les surfaces du quai et de la digue sont légitimement claires et doivent rester intactes. Reproduction native de même nature à 5.934167° E / 43.085278° N, Z16.3, bearing 315°, pitch 45° ; cadrage proche, non déclaré identique.

## 4. Analyse de `eaux_pix.jpg`

Fichier réellement ouvert. SHA-256 `f328a994b394d876eb1c0672640e0f4946ee8599f7916ac5879aed5b74229511`.
Observation : Z13.8 ; quais Milhaud, rade de Toulon, blocs en pleine eau et transitions orthogonales. La photo seule ne distingue pas les cellules de données des tuiles XYZ. Reproduction native vers 5.915° E / 43.105° N, Z13.8, cap 0°, pitch 63.75° : mêmes ouvrages et même mosaïque, cadrage différent.

## 5. Analyse complémentaire de `artefacts_cotiers_avant.jpg`

Original ouvert et conservé. SHA-256 `73c9a0f1ae2d24df57657a78bc2cf41cdd8bf5ec456429561cc14daf6e367475`.
Bandes bleu nuit de l'ancien fond à Z15.3. Cette référence sert à vérifier que remplacer le gris ne restaure pas ce défaut. Le commit initial garde le gris comme indication du manque de couverture ; la présente mission autorise une reconstruction **de couleur d'affichage** à partir de voisins valides, sans nouvelle mesure de profondeur.

## 6. Audit technique n°1 — avant toute correction

### Pipeline relu

| Étape | Responsabilité | Transformations / limites |
| --- | --- | --- |
| XYZ → bbox | `web_mercator_tile_bbox` | EPSG:3857, y XYZ vers le sud, grille globale. |
| WMS | `fetch_bathymetry_tile`, `_request_tile` | 256+halo3=262 px, `mean_multicolour`, transparence, une requête, HTTP/1.1, timeout/retries ; **aucun paramètre d'interpolation**, défaut fournisseur identifié par comparaison. |
| RGB | `recolor_bathymetry_png`, `_blue_color_lut` | LUT 33³ basée sur la légende, pas une profondeur ; alpha réappliqué ; lissage prémultiplié 0.65 px. |
| Couverture | `feather_coverage` | Alpha minimum du fournisseur et d'un flou 0.8 px, uniquement vers l'intérieur ; crop256. |
| Masque | `rasterize_ocean`, `CoastlineMask.get_mask` | Union eau/docks/canaux, trous conservés, suréchantillonnage4 et centres Shapely ; les surfaces `pier_polygons` n'étaient pas retirées de l'union eau. |
| Caches | `fetch_bathymetry_tile`, `MarineHTTP`, `BathymetryTileCache` | LRU512 fournisseur ; OSM persistant≥7j, masques512/8Mio ; final RAM32Mio, SQLite128Mio, 24h, version `marine-palette-3`, single-flight/concurrence8/queue128. |
| API | `_render_bathymetry_tile`, `get_bathymetry_tile` | Alpha vide : masque évité ; sinon clip eau ; erreurs503 ; PNG public24h. |
| Mapbox | `MarineMapController`, `GlobeStyle` | 256 px, maxzoom14, LINEAR, MIDDLE dès Z5 ; fond eau BOTTOM gris `#93ACB0` dès Z5. Le LINEAR du moteur ne peut reconstruire une interpolation absente à l'intérieur des cellules déjà agrandies par le WMS. |

### Tableau du gris

| Hypothèse / fichier | Preuve et contre-exemple | Conclusion / correction envisageable |
| --- | --- | --- |
| H1 fond sous raster, `globe_style.dart` | La couleur exacte du fond est grise ; les pixels fournisseur transparents la révèlent. Les quais opaques sont d'autres objets. | Confirmé, confiance forte ; remplacement local à partir de voisins d'eau et distinction des données. |
| H2 couverture WMS | Les dix tuiles conservées de l'audit antérieur contiennent des zones sans couverture dans l'eau OSM. Une tuile entièrement transparente ne fournit aucun voisin exploitable. | Confirmé localement ; s'abstenir sur les grandes absences non soutenues. |
| H3 masque, `coastline.py` | Les centres eau sont conservés ; en revanche certains pier polygons intersectent l'océan (16 centres sur 8462/6014 ; 26 sur 8461/6012). Sur 8461/6012, 7 pixels gris se trouvent sur ces ouvrages réels. | Garde-fou indispensable : retirer les surfaces de jetées du domaine d'eau avant reconstruction. Ne pas recolorer tout gris. |
| H4 LUT / prémultiplication | Alpha exactement conservé par LUT, feather réducteur ; ne fabrique pas ces larges plages. | Contredit comme origine principale ; conserver ces garanties. |
| H5 surfaces portuaires réelles | Digues/quais sont visibles dans les deux photos et l'Android. L'analyse MVT confirme le cas de structures dans l'océan. | Confirmé pour certaines surfaces grises légitimes ; protection géométrique, aucun filtre global de couleur. |

### Tableau de la mosaïque

| Hypothèse / fichier | Preuve / contre-exemple | Conclusion / correction envisageable |
| --- | --- | --- |
| Raccord XYZ | 13 recouvrements de halo conservés : alpha et RGB identiques. | Pas la cause principale dans ces cas ; ne pas déplacer les bbox. |
| Grille fournisseur et rééchantillonnage WMS | Requête de référence exactement reproduite avec `interpolations=nearest neighbor` (pixels RGB/alpha identiques). La même bbox en bilinéaire change 62869 pixels RGB et réduit les aplats. | Confirmé ; tester l'interpolation WMS, sans augmenter dimensions/maxzoom. |
| Mapbox LINEAR absent | Présent dans le code et le style natif. | Contredit ; le surzoom amplifie les aplats déjà présents. |
| Palette LUT | La rampe produit un gradient continu dans les tests ; elle transmet les cellules déjà aplaties par le fournisseur. | Pas de changement de palette justifié. |
| Cache ancien | La requête WMS directe reproduit les blocs hors caches NoWave. | Pas la cause, mais versionner toute nouvelle génération. |

Expérience WMS 262×262, une requête par variante : nearest 13244 octets / 0.800s ; bilinear 70037 / 0.533s ; bicubic 66961 / 0.759s. Mesures ponctuelles non comparables comme benchmark réseau. Sur pixels opaques, proportion de voisins horizontaux RGB identiques : 75.68% nearest → 19.30% bilinear. Gradient RGB moyen au percentile95 : 3.33 → 1.67. Le bicubique introduit beaucoup plus d'alpha partiel (11210 pixels contre284), sans avantage établi.

Sources primaires : [EMODnet Bathymetry](https://emodnet.ec.europa.eu/en/bathymetry) (grille finie ~115m, aucune précision nouvelle promise), [paramètre WMS GeoServer](https://docs.geoserver.org/main/en/user/services/wms/vendor/), [surzoom Mapbox](https://docs.mapbox.com/style-spec/reference/sources/). L'acceptation effective du paramètre est **mesurée**, pas supposée depuis la documentation.

## 7. Audit technique n°2 — contre-vérification avant correction

Deuxième passe par une méthode distincte, même intervenant ; aucune revue humaine indépendante revendiquée.

- Relecture des fonctions et vérification fournisseur indépendante du rendu Android : nearest reproduit exactement l'entrée de référence, bilinear apporte de vraies transitions d'image sans données supplémentaires.
- Les interpolations changent également l'alpha **fourni par le serveur** : 284 pixels diffèrent nearest/bilinear. La correction B doit conserver l'alpha de son entrée bilinéaire ; ne pas annoncer l'égalité avec une requête nearest différente.
- Deux bbox adjacentes bilinéaires : 1572 pixels de halo communs, **0 différence alpha et 0 différence RGB** sur pixels valides. Le bilinéaire ne révèle pas de couture dans ce premier contrôle ; étendre aux deux axes et quatre tuiles en tests.
- Le halo OSM n'existe pas dans les fichiers réels examinés : ocean s'arrête exactement à 0..4096. Ne pas inventer une géométrie hors tuile. Une reconstruction proche d'une frontière nécessite les masques voisins, avec le cache OSM existant.
- Les surfaces de jetées qui chevauchent l'océan ne doivent ni donner une couleur, ni être des cibles. Aucun buffer arbitraire autour d'une ligne d'ouvrage n'est justifié.
- Reconstitution indépendante Shapely/centres de l'audit précédent confirme les trous et l'absence d'érosion des centres d'eau. Le défaut principal du gris reste le fond statique ; le garde-fou pier protège les cas légitimes.
- Une reconstruction locale est autorisée par la règle produit, mais elle doit rester bornée et déclarée **visuelle**, conserver la couverture source séparément, ne pas se propager de pixel reconstruit en pixel reconstruit et s'abstenir sans donneurs suffisants.
- Un lissage gaussien global masquerait la résolution sans traiter le rééchantillonnage. Le paramètre bilinéaire est préféré à une augmentation de tileSize/maxzoom ou à un flou massif.
- Source totalement transparente, masque vide, pixels partiels, îles, bassins, digue, bords/corners, cache/reload et écran Android restent à couvrir dans les validations ciblées ; aucun succès futur présumé.

Conclusion avant correction : preuves suffisantes pour **A**, reconstruction locale des couleurs d'affichage limitée à l'eau et protégée contre les ouvrages, puis **B**, interpolation bilinéaire côté WMS. L'interpolation ne constitue pas une amélioration de précision hydrographique. Aucun changement de sonde ni valeur de profondeur autorisé.

## 8. Cause racine du gris parasite

Couverture visuelle manquante ou partielle révélant un fond uniforme gris. Certaines surfaces grises sont de vrais ouvrages : elles ne sont pas des cibles. La correction A doit distinguer ces deux cas par géométrie et provenance, jamais par la teinte grise seule.

## 9. Cause racine de la pixellisation

Le WMS agrandit par plus proche voisin une grille de résolution finie ; ces aplats existent dans l'image avant NoWave et sont renforcés par les zooms élevés. Les limites de tuiles ne sont pas responsables des blocs intérieurs étudiés. La correction visuelle B porte sur le mode de rééchantillonnage fournisseur, avec vérification des coûts et de l'alpha.

## 10. Correctif A : modifications et preuves

Implémenté et vérifié **avant le correctif B**. Le WMS conserve encore son échantillonnage nearest à cette étape.

- Contexte fini de 8 pixels autour de la tuile, une requête WMS de 272×272 au même pas natif. Pas de hausse de tileSize ou maxzoom.
- Donneurs : pixels d'eau OSM entièrement couverts par le fournisseur ; aucun donneur terrestre, aucun pixel reconstruit réutilisé comme source.
- Couleur locale par pondération triangulaire de support fini 17×17, au moins huit donneurs et poids minimal5%. Pas de flood-fill, pas de propagation illimitée, pas de lissage des RGB valides.
- Cibles : transparence manquante ou partielle dans l'eau identifiée. Grandes absences non soutenues : abstention ; fond gris conservé comme indication d'insuffisance.
- Masque eau privé des surfaces `pier_polygons` qui chevauchaient l'océan : protection des vrais ouvrages, source et cible. Aucune largeur arbitraire inventée pour les lignes de digue.
- Hors frontière, masques voisins réels via le cache OSM existant. Les voisins ne sont demandés que lorsqu'un candidat nécessite ce contexte. Pas de tuile EMODnet voisine supplémentaire.
- **Distinction essentielle :** l'alpha de la couche d'affichage peut augmenter localement pour porter la couleur de remplacement demandée. La couverture source ne change pas : elle est conservée exactement dans `NoWave.SourceCoverage` (alpha 8 bits 256×256, base64, texte PNG compressé), avec nombre de pixels reconstruits et usage explicite. Ne pas présenter l'alpha d'affichage comme une emprise de mesures. Les données numériques hydrographiques ne sont jamais lues par cet algorithme.
- URL/cache intermédiaires `marine-visual-4`. Attribution et en-têtes HTTP identifient le rendu visuel, sans nouvelle mesure.

## 11. Validation intermédiaire A

Tests ciblés : **72 passed** Python, **14 passed** Flutter. Première exécution Python : 68 réussites / 4 échecs dans les nouveaux tests, causés par deux assertions mélangeant les coordonnées Pillow(x,y) et NumPy[y,x] ; correction de ces coordonnées, puis72 réussites. Le comportement produit n'a pas été modifié pour contourner ces tests.

API locale réellement testée sur 14/8462/6014 : HTTP200, version 4, 6141 octets, 210 pixels reconstruits ; couverture source avec140 pixels alpha0, affichage avec58 pixels alpha0. Les82 pixels devenus visibles restent marqués sans couverture dans le champ conservé ; les pixels partiels complètent le total210. Premier appel1.1181s, second identique1.1ms. L'ancien rendu final n'est pas réutilisé.

Android réel, même caméra que le baseline : la grande plage grise près de la digue devient turquoise cohérent. La digue et le quai restent clairs ; sondes et balises conservées. Le style natif annonce `http://127.0.0.1:8004/` et la version 4, et les requêtes sont observées sur le backend local. La mosaïque en pleine eau reste visible : A n'est pas présentée comme une correction de B.

Preuves intermédiaires conservées ; passage à B uniquement après cette inspection.

## 12. Correctif B : modifications et preuves

B a été commencé **après** la validation intermédiaire A.

1. Paramètre WMS `interpolations=bilinear`, sans augmentation du zoom disponible ni de la résolution spatiale demandée. Les 256 pixels utiles représentent toujours la même bbox et le même pas.
2. Première expérience `marine-visual-5` : mosaïque réduite, mais frange sombre près des ouvrages, **rejetée après inspection Android**, malgré des tests automatiques verts. Le fournisseur encode des RGB associés à l'alpha sur les pixels partiels : par exemple RGBA(84,34,37,95), au lieu d'une couleur droite voisine. La LUT non linéaire interprétait cette atténuation comme une teinte profonde.
3. Normalisation des RGB associés **avant** la LUT, uniquement pour la réponse bilinéaire WMS. `recolor_bathymetry_png` conserve son fonctionnement générique avec alpha droit par défaut. Sur l'entrée réelle examinée : 182 pixels partiels devenaient trop sombres sans normalisation ; aucun pixel pleinement opaque ne présentait cette dérive. L'alpha est conservé exactement par la recolorisation ; le feather hérité reste réducteur.
4. Version intermédiaire `marine-visual-6` : frange supprimée sur Android. Un test à alpha 64 avait une tolérance RGB initiale trop stricte (écart mesuré4/255 contre tolérance3). Le test utilise maintenant la borne de quantification des deux associations 8 bits, `2*ceil(255/alpha)`, sans relâcher l'égalité exacte de l'alpha ni accepter une frange sombre.
5. La deuxième revue technique a identifié le **support combiné** des filtres : le rayon de reconstruction8 doit être séparé du halo WMS, qui doit aussi porter les3 pixels du prétraitement. Version finale **`marine-visual-7`**, halo12 (8+3+garde1), image WMS **280×280**, sortie **256×256**. Trois tests combinés comparent les mêmes pixels sous des découpages décalés horizontalement, verticalement et diagonalement ; égalité exacte.

Aucune palette modifiée, aucun lissage global massif, aucune nouvelle texture, source Mapbox ou couche. Le lissage subpixel existant reste à 0.65 ; le bilinéaire est effectué au bon endroit, avant que les cellules fournisseur soient figées dans le PNG. Les variations réelles de teinte restent visibles, sans nouvelle sonde ou profondeur déduite.

## 13. Validation intermédiaire B

- Essai bilinéaire initial : **79 tests ciblés réussis**, mais rendu Android refusé à cause de la frange. Ce résultat n'est pas présenté comme une validation visuelle.
- Normalisation alpha : première passe **81 réussites, 1 échec** sur la tolérance de quantification alpha 64 expliquée ci-dessus.
- Final après sécurisation du halo, tests API et caches compris : **86 tests ciblés réussis**, 2.93s.
- Android : mosaïque fortement réduite à Z13.8, continuité turquoise conservée à Z16.3, pas de retour de la bande bleu nuit. L'essai refusé et les captures corrigées sont conservés séparément.
- Dix tuiles réelles aux niveaux Z12, Z13 et Z14 : une requête WMS par tuile, puis réutilisation sans deuxième requête dans le même processus ; couverture source récupérée exactement et aucun alpha d'affichage supérieur au masque d'eau.
- Comparaison des halos finaux : dix couples, 6720 pixels communs par couple ; **alpha identique sur les dix**, RGB strictement identiques sur huit couples et écart maximal **1/255** sur deux couples. Ce petit arrondi vient déjà du fournisseur ; il n'est pas présenté comme une égalité parfaite. Aucun raccord rectangulaire visible dans la recette native. Les tests avec entrées identiques, eux, vérifient l'égalité exacte des sorties.

## 14. Fichiers modifiés

Code applicatif :

- `backend/app/infrastructure/adapters/emodnet_bathymetry.py` : bilinéaire WMS, normalisation du RGB associé, contexte indépendant du recadrage public.
- `backend/app/infrastructure/marine/visual_water.py` : nouvelle reconstruction locale de couleur, abstention, conservation de la couverture, sortie PNG et voie rapide sans reconstruction.
- `backend/app/infrastructure/marine/coastline.py` : protection des surfaces de jetées et assemblage des masques voisins nécessaires.
- `backend/app/infrastructure/marine/bathymetry_cache.py` : version 7 ; budgets et politique inchangés.
- `backend/app/api/routes/map_tiles.py` : composition du rendu, recadrage vide, en-têtes de version et d'usage visuel ; mêmes routes, formats et erreurs503.
- `mobile/lib/core/map/marine/marine_map_controller.dart` : URL versionnée7 et mention d'attribution précise.

Tests : `test_visual_water.py`, `test_bathymetry_sampling.py`, `test_emodnet_bathymetry.py`, `test_coastline.py` existant exercé sans modification, `test_bathymetry_cache.py`, `tests/api/test_map_tiles.py`, tests Flutter du contrôleur marin et des bases API. La documentation du test historique `test_coastal_raster_artifacts.py` précise désormais qu'il protège le chemin de couverture source **avant** reconstruction visuelle ; ses assertions sont conservées.

Documentation : `docs/architecture/marine-sources.md`, `marine-zoom-persistence.md`, ce rapport et ses preuves dans `artifacts/NW-220-gray-pixelation/`. Aucun changement de `map_screen.dart`, `MarineZoom`, palette, positions GPS, signalements ou symboles nautiques.

## 15. Tests créés ou mis à jour

**41 nouveaux cas** par rapport au SHA initial :

- 15 cas de reconstruction visuelle : turquoise et bleu foncé, terre/quai/digue, manque de support, grande absence, alpha partiel, masque vide, frontières et quatre coins, protection des surfaces de jetées, contexte OSM conditionnel et réutilisé.
- 19 cas de rééchantillonnage : gradient horizontal/vertical/quatre coins, couleur constante, vraie transition, absence de données, alpha partiel, une requête par tuile et absence de nouvelle requête sur réutilisation, zooms fractionnaires/surzoom.
- 3 cas combinant prétraitement et reconstruction sous des découpages XYZ décalés ; contrôle du halo cumulé et égalité exacte des pixels communs.
- 3 cas de RGB associés à alpha 64/128/192 : pas de fausse classe profonde, alpha exact, borne de quantification expliquée.
- 1 cas API bout en bout : provenance de couverture dans le PNG, image d'affichage, version/usage, cache chaud partagé.

Les tests existants du WMS et des routes ont été adaptés au contexte280 et au nouveau compositeur, sans supprimer les contrôles503 ou transparence vide. Le test de cache vérifie que les versions2,3,4,5,6 restent sur disque mais ne servent pas à la version 7 ; plafonds RAM/disque conservés. Les tests Flutter gardent maxzoom14, minzoom5, LINEAR, slot, cache, rechargement et séparation des URL métier/marine.

## 16. Résultats exacts des tests

Environnement existant : Python 3.14.4 / Flutter 3.47.6 / Dart 3.13.5. Aucune installation ni mise à jour de dépendances. NumPy était déjà présent dans le verrou de production via les dépendances existantes ; la nouvelle fonction l'utilise directement. La différence avec les versions documentées de CI reste signalée.

| Contrôle réellement exécuté | Résultat |
| --- | --- |
| Baseline Python ciblée avant modifications | **57 passed**, 1.88s, 1 avertissement existant |
| Première validation A | 68 passed / 4 failed : coordonnées d'assertions x/y inversées dans les nouveaux tests, corrigées |
| Validation A corrigée | **72 passed**, 1.91s |
| Flutter ciblé A | **14 passed** |
| Première expérience B | **79 passed**, rendu Android ensuite refusé |
| Première normalisation B | 81 passed / 1 failed : borne de quantification alpha 64, justifiée et corrigée |
| Python ciblé final7 | **86 passed**, 2.93s |
| `dart format --output=none --set-exit-if-changed lib test` final | **243 fichiers, 0 changé**, 0.52s |
| `flutter analyze --no-pub` final | **No issues found**, 3.6s |
| `flutter test --no-pub --reporter expanded` final | **881 réussites, 0 échec**, environ41s |
| Suite backend complète finale avec PostGIS isolé | **1324 passed, 2 skipped, 0 failed/error**, 49.27s |
| `ruff check backend` | **All checks passed** |
| Rejeu hors réseau des dix entrées conservées | **10/10** : pixels et couverture identiques, alpha borné par l'eau |
| `git diff --check` final | Réussi |

La première passe du formatage avait détecté un fichier de test Flutter à reformater ; il a été formaté, puis les contrôles complets ont été rejoués. Les suites finales n'ont pas d'échec intermittent caché. Les deux skips backend : archives locales SHOM XYZ absentes (hors sondes MVP) et sonde Nginx non activée faute de `NOWAVE_TEST_NGINX`. Avertissement existant Starlette/TestClient/httpx ; aucune dépendance modifiée pour le faire disparaître.

Commandes principales :

```sh
.venv/bin/python -m pytest backend/tests/unit/test_bathymetry_sampling.py backend/tests/unit/test_visual_water.py backend/tests/unit/test_coastline.py backend/tests/unit/test_emodnet_bathymetry.py backend/tests/unit/test_bathymetry_cache.py backend/tests/api/test_map_tiles.py -q
NOWAVE_TEST_PORT=55434 docker compose -p nowave-gray-review -f compose.test.yaml up -d --wait --wait-timeout 90 database
NOWAVE_TEST_ADMIN_URL=postgresql://nowave_ci:ci-test-only@127.0.0.1:55434/nowave_ci .venv/bin/python -m pytest backend/tests -q --junitxml=/tmp/nowave-gray-backend-v7.xml
NOWAVE_TEST_PORT=55434 docker compose -p nowave-gray-review -f compose.test.yaml down
```

Le conteneur PostGIS dédié était sain ; les fixtures créent une base à nom aléatoire. Conteneur et réseau retirés après la suite, aucun volume de développement touché. Les journaux finaux et rouges intermédiaires sont joints dans le dossier `validation/`.

## 17. Résultats de la recette Android

Appareil réellement vérifié par ADB et Flutter : **LGN LX1, Android 15 API 35, AV5PJV6328H03108**, écran 720×1610, densité physique 320 dpi. Pas de simulation de GPS, de création de signalement, de désinstallation ou d'effacement des données.

Le backend a été lancé localement, sans déploiement :

```sh
PYTHONPATH=backend MARINE_CACHE_DIR=/tmp/nowave-gray-cache .venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 8004
adb -s AV5PJV6328H03108 reverse tcp:8004 tcp:8004
cd mobile
flutter run -d AV5PJV6328H03108 --dart-define-from-file=.env.json --dart-define=MARINE_API_BASE_URL=http://127.0.0.1:8004/ --no-pub --host-vmservice-port=8181
```

Le fichier privé `.env.json` est intact ; la base métier habituelle est conservée. L'application installée utilise réellement la version 7 du backend local, contrôlée dans les objets de style du moteur Android et par l'en-tête HTTP. Les reconstructions et redémarrages ont conservé le compte et les données du téléphone.

Parcours final **rejoué intégralement sur version 7** :

- Gris : Z13,14,15,16,16.3 à 5.934167/43.085278, cap 315°, pitch 45°.
- Mosaïque : Z12,13,13.8,14,15,16 à 5.915/43.105, cap 0°, pitch 63.75°.
- Référence côtière historique :5.927/43.109, Z15.3.
- Marseille :5.365/43.295, Z13.8 et16.3.
- Côte naturelle : Porquerolles6.205/43.0, Z14.
- Pleine eau :5.94/43.064, Z16.3.
- Courbes offshore :5.9293/43.0637, Z13→Z16→Z13 ; **26 identifiants exactement identiques**, lignes et étiquettes visibles. Le nombre rendu varie normalement avec l'emprise.
- Série rapprochée de déplacements/zooms/rotations Z12→16.3→13, glissement tactile ADB réel, rechargement du style, retour sur la digue.
- Menu d'attribution ouvert et parcouru : mention « couleurs interpolées localement pour l'affichage, sans mesure ajoutée » réellement visible, capture et hiérarchie UI conservées.

Les **23 captures finales** ont toutes **0 erreur marine**, aucune requête active et aucun dernier échec non résolu. À Z12, pas de sonde placée ; à partir de Z13, sondes, courbes et marques apparaissent selon les règles existantes. Les zooms fractionnaires ne sont pas des XYZ fractionnaires : les sources utilisent des niveaux entiers, plafonnés à14, et le moteur surzoome les tuiles aux zooms16/16.3. Les entrées fournisseur ont aussi été examinées explicitement aux niveaux 12 et13.

**Incident conservé, non masqué :** la recette intermédiaire version 6 avait compté un `StateError` sur une tuile de dangers13/4232/3008. Réponse HTTP200, corps10671 octets, pas un échec PNG. Les seules branches StateError et les compteurs identifient le garde-fou de budget du viewport existant, sans changement de ce composant. Contre-vérification : état `ok`, plus de dernier échec,0 requête active ; le compteur cumulatif reste1 et n'a pas été remis à zéro pour cacher l'incident. La recette finale démarrée sur version 7 enregistre0 erreur sur23 captures.

La carte corrigée est laissée sur le téléphone avec le backend local8004 actif. Elle dépend de ce backend et du reverse USB ; le résultat n'est pas annoncé comme déployé sur l'API publique.

## 18. Comparaisons visuelles avant/après

Comparaisons réellement ouvertes :

- [Gris avant](artifacts/NW-220-gray-pixelation/before-gray.png), [A intermédiaire](artifacts/NW-220-gray-pixelation/intermediate-A-gray.png), [après final7](artifacts/NW-220-gray-pixelation/after-gray.png).
- [Mosaïque avant](artifacts/NW-220-gray-pixelation/before-pixels.png), [après final7](artifacts/NW-220-gray-pixelation/after-pixels.png).
- [Essai B5 refusé pour frange sombre](artifacts/NW-220-gray-pixelation/rejected-B5-dark-fringe.png).
- [Non-régression côtière](artifacts/NW-220-gray-pixelation/after-historic-coast.png), [second port](artifacts/NW-220-gray-pixelation/after-marseille.png), [côte naturelle](artifacts/NW-220-gray-pixelation/after-natural-coast.png).
- [Planche des zooms](artifacts/NW-220-gray-pixelation/android-zooms.png), [validation combinée](artifacts/NW-220-gray-pixelation/android-combined.png), [explication native](artifacts/NW-220-gray-pixelation/attribution.png).

Indicateur sRGB, région fixe(320,720)-(610,1060) de la digue : **15571 pixels classés gris avant, 546 après A, 542 après final7**. Le seuil inclut des ouvrages légitimes ; les valeurs restantes ne sont pas toutes des anomalies. L'inspection des grandes images distingue le corps clair de la digue, conservé, de la plage grise sur l'eau, supprimée. Pas d'assertion d'identité pixel par pixel des anticrénelages des ouvrages : leur fond a volontairement changé.

Les formes bathymétriques persistent, leurs contours colorés deviennent plus doux ; les blocs rectangulaires sont fortement réduits. Une résolution source finie n'est pas transformée en détail hydrographique réel. Aucune comparaison automatique avec la photographie utilisateur n'est présentée comme un cadrage exact.

## 19. Impact sur les performances

Mesures locales, pas des promesses de performance universelle :

| Indicateur | Mesure finale |
| --- | --- |
| Tuile utile / source Mapbox | **256×256**, inchangé |
| Contexte WMS |280×280 contre262×262 initialement : **+14.2% de pixels**, au même pas ; marge nécessaire aux supports cumulés, pas une nouvelle résolution bathymétrique |
| Nombre de GetMap | **1 par tuile froide**,10/10 cas réels ;0 nouvelle requête sur répétition dans le même processus |
| PNG final de l'exemple14/8462/6014 |**22936 octets**, contre5510 dans la référence précédente ; hausse d'entropie due au gradient et métadonnées, pas hausse de dimensions |
| Dix PNG réels finaux |2530 à56041 octets, moyenne31756 |
| Traitement visuel des dix tuiles réelles |moyenne 16.60ms, maximum 20.17ms, hors téléchargement WMS |
| Microbench synthétique,15 répétitions |eau opaque2.13ms / trou local10.75ms / absence totale1.33ms en moyenne ; les voies sans reconstruction évitent les gros buffers |
| Pic mémoire tracé par appel synthétique |environ1.22Mio sans reconstruction,11.24Mio avec reconstruction ; allocation transitoire,8 rendus concurrents au maximum |
| API locale chaude, exemple |1.775ms puis0.618ms, mêmes octets et version 7 |

La convolution de reconstruction est finie, vectorisée et exécutée côté backend dans un thread. Elle ne s'applique pas aux RGB valides et ne rajoute pas de travail Dart par frame. Les PNG bilinéaires sont effectivement plus volumineux : ce coût est accepté pour la continuité demandée, tout en gardant les plafonds de cache. Aucun téléchargement WMS des tuiles voisines ; les masques OSM additionnels sont conditionnels et réutilisent le cache durable et son sémaphore existant.

**Mesures natives à ne pas masquer :** en fin de parcours debug étendu, Android indique PSS713098kB, RSS779832kB. `gfxinfo` rapporte1342 frames HWUI,144 janky(10.73%), médiane5ms et percentile95 à46ms. Ces métriques ne mesurent pas seules la totalité du rendu Flutter/Mapbox et il n'y a pas de baseline release équivalente. La mémoire absolue est importante ; aucune baisse de mémoire ou absence de régression native universelle n'est revendiquée. Les dimensions des textures, sources/layers, budgets mobiles et logique par frame restent structurellement inchangés. Les manipulations, captures et informations finales sont conservées pour un profilage comparatif ultérieur.

## 20. Gestion des caches

- Cache Python fournisseur : même LRU512, données de contexte en mémoire seulement ; processus redémarré entre les variantes. Pas de réemploi d'un ancien code sous une nouvelle version.
- Cache final RAM32Mio / SQLite128Mio / TTL24h / single-flight / concurrence8 / queue128 inchangés.
- Versions d'expérimentation4,5,6 et finale7 séparées ; fichier SQLite final inspecté en lecture seule, anciennes lignes encore présentes. Tests spécifiques pour les anciennes versions2,3,4,5,6.
- Source Flutter `v=marine-visual-7`, cache backend `marine-visual-7`, réponse HTTP version 7 vérifiés conjointement sur appareil.
- Cache HTTP public24h conservé ; nouvelle URL évite le mélange avec les anciennes images Mapbox/HTTP. Aucun cache de production purgé.
- OSM : réponses brutes persistantes au moins7 jours, masques RAM512 /8Mio ; redécodage du masque avec la protection des jetées après redémarrage. Les masques voisins ne sont ni inventés par prolongement d'un polygone tronqué ni demandés systématiquement neuf par neuf.

Les pixels sans données du fournisseur et l'alpha de couverture restent distinguables : l'alpha d'affichage est une composition visuelle, `NoWave.SourceCoverage` conserve la couverture **après les traitements hérités et le masque, avant reconstruction**. En absence de reconstruction, l'alpha final est déjà cette couverture. Ni le PNG ni son texte ne doivent être présentés comme une nouvelle mesure de profondeur.

## 21. Double validation finale

### Validation n°1 — fonctionnelle et visuelle

Inspection des grandes comparaisons et des deux planches natives finales : grandes plages grises supprimées dans les scénarios reproduits, continuité bleue/turquoise cohérente, forte réduction de la mosaïque, frange sombre B5 supprimée. Les quais/digues restent lisibles et clairs ; les surfaces terrestres ne sont pas des cibles. Sondes, courbes et marques conservées. 0 erreur marine sur les23 captures finales, courbes à identifiants stables, navigation de caméra et rechargement exercés réellement.

### Validation n°2 — technique et régressions

Diff relu intégralement, nouveaux fichiers et tests inclus. Cette passe a trouvé puis fait traiter le cumul des supports de filtrage : halo12 séparé du rayon8, trois tests combinés d'égalité des pixels. Vérification des erreurs503, données vides, alpha partiel, îles/jetées, coins, abstention et ancienne version de cache. Les mesures réelles confirment la conservation de couverture et l'absence d'alpha au-delà de l'eau. Aucune modification de coordonnées, valeur numérique, symbole, seuil `MarineZoom`, collision portuaire ou gestion de statut vectoriel.

Budgets et coûts relus : aucune dépendance installée, nouvelle couche Mapbox, hausse de maxzoom/tileSize, boucle mobile par frame ou requête WMS par voisin. Les coûts CPU/PNG augmentent de façon mesurée et bornée ; les plafonds sont conservés. Les limites natives de performance ne sont pas transformées en succès non mesuré.

**Concordance :** les deux anomalies ont des causes distinctes et les deux correctifs se composent correctement dans les cas vérifiés. Pas de divergence bloquante identifiée sur la validité des pixels et des données ; le profilage release comparatif reste hors preuve, explicitement documenté.

## 22. Risques résiduels

- Couleur reconstruite = habillage, jamais précision ou profondeur nouvelle. Couverture source séparée et attribution explicite ; grands trous sans donneurs suffisants restent inconnus/gris.
- Résolution native EMODnet finie ; ni le bilinéaire ni l'affichage ne permettent d'affirmer une meilleure précision bathymétrique.
- Normalisation du RGB associé fondée sur le comportement bilinéaire réellement observé ; si le fournisseur change ce comportement, cette convention devra être revérifiée. La quantification 8 bits des pixels très transparents impose un petit arrondi, documenté/testé.
- Géométries OSM/Mapbox et ouvrages cartographiques peuvent différer ailleurs ; les cas testés ne prouvent pas tous les ports. Aucune largeur arbitraire n'est inventée pour un ouvrage publié seulement comme ligne.
- PNG plus gros et reconstruction backend plus coûteuse, avec limites mémoire/concurrence conservées. Mémoire native debug élevée et saccades mesurées, sans baseline release comparative ; ne pas annoncer une validation de performance universelle.
- iOS non testé. Deux tests optionnels ignorés et versions locales différentes de la CI, détaillés plus haut.
- Application actuellement liée au backend marin local8004 et au reverse USB. Aucun changement disponible en production tant qu'une livraison distincte n'est pas autorisée.

## 23. Verdict : prêt ou non pour commit et PR

**Prêt pour revue, commit local et PR du correctif après décision explicite de l'utilisateur**, sur le périmètre visuel et les scénarios démontrés : causes identifiées, A validée avant B, fortes améliorations natives observées,41 nouveaux cas et suites finales vertes, couvertures et données numériques préservées, caches cohérents. Ce verdict ne vaut ni autorisation de publication, ni validation iOS/release, ni garantie de performance native sans comparaison équivalente.

À la clôture des validations, les originaux et les sept fichiers protégés sont identiques aux empreintes initiales, l'index est vide, la branche est `fix/NW-220-coastal-raster-artifacts`, HEAD `433c7bad`, `dev` local `c0361be7`. Aucun commit, push, PR, merge, changement de `dev`, modification Linear ou déploiement n'a été réalisé pendant cette phase.

**Autorisation ultérieure :** l'utilisateur a explicitement demandé « fais le commit et le push ». Le correctif, ses tests, sa documentation et ses preuves sont donc inclus dans un nouveau commit et poussés sur cette branche. Les répertoires protégés `docs/design/` et `mobile/codex_photo/` restent exclus. Cette demande n'inclut aucune PR, fusion dans `dev` ou mise en production.

[Inventaire des preuves et rejeu hors réseau](artifacts/NW-220-gray-pixelation/README.md).
