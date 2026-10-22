# NW-220 — Audit des artefacts bathymétriques côtiers

> **Sélection des preuves pour la PR #125 :** ce rapport décrit la recette historique. Les captures intermédiaires et journaux volumineux ont ensuite été retirés du diff par un commit normal ; les résultats et incidents décrits ci-dessous restent historiques. Les liens vers les preuves retirées pointent vers le commit initial immuable. Voir [l’inventaire et les décisions](NW-220-PR125-evidence-inventory.csv) et le README des preuves pour la sélection actuelle et les commandes de reproduction. Les nouveaux résultats complets sont publiés comme artefacts GitHub Actions.

## État initial et périmètre

- Date locale : 22 octobre 2026, Europe/Paris.
- Branche autorisée : `fix/NW-220-coastal-raster-artifacts`.
- SHA de départ : `c0361be7` (identique au `dev` local et à `origin/dev` lors du contrôle).
- `git diff --check` initial : succès, aucun changement suivi initial.
- `docs/design/` et `mobile/codex_photo/` : préexistants, non suivis, préservés ; inventaire SHA-256 des 5 fichiers enregistré avant intervention.
- Aucune publication, aucun commit, push, merge, déploiement ou changement Linear autorisé.

## Photo de référence — observation réelle

Fichier ouvert : `mobile/codex_photo/artefacts_cotiers_avant.jpg`, 136 666 octets.
SHA-256 : `73c9a0f1ae2d24df57657a78bc2cf41cdd8bf5ec456429561cc14daf6e367475`.
L'original est conservé intact.

Observations : badge Z15.3, eau turquoise, sondes et balisage visibles ; bandes bleu nuit autour des quais rectilignes en haut, bassin à droite et promontoire en bas. Certaines limites sont orthogonales et en escalier. La photographie seule ne prouve ni une erreur de géométrie, ni une profondeur réelle, ni un défaut de slot.

Le GPS `43.085278, 5.934167` est une indication de reproduction, pas une géolocalisation certaine de tous les ouvrages photographiés. La première reproduction native utilise ce point à Z15.3, cap 0°, inclinaison 45° et montre le même type d'artefact autour d'une jetée et du littoral de Saint-Mandrier. Ce n'est pas le cadrage exact de la photo initiale.

## Audit 1 — avant correction

### Pipeline reconstitué

| Étape | Fonction / fichier | Transformation et limites |
| --- | --- | --- |
| XYZ → WMS | `web_mercator_tile_bbox`, `fetch_bathymetry_tile`, `emodnet_bathymetry.py` | Bbox EPSG:3857, XYZ nord vers sud, pixels 256, halo 3 pixels, requête 262×262 ; `mean_multicolour`, transparence demandée. |
| Réseau | `_request_tile` | HTTP/1.1, timeout 10 s / connexion 3 s, retries 0,25/0,75 s sur transport, 429/502/503/504 ; exceptions explicites, contrôle MIME/PNG/dimensions. |
| Palette | `recolor_bathymetry_png`, `_blue_color_lut` | Projection RGB sur rampe observée, LUT 33³, aucune conversion en profondeur. Alpha source réappliqué exactement ; flou RGB prémultiplié 0,65 px pour éviter les franges noires/blanches. |
| Couverture | `feather_coverage` | Minimum entre alpha initial et flou 0,8 px : atténuation vers l'intérieur seulement ; recadrage du halo en 256×256. |
| Masque | `CoastlineMask.get_mask`, `rasterize_ocean`, `coastline.py` | Surfaces `ocean`, docks et canaux Shortbread ; union géométrique, trous des îles ; suréchantillonnage ×4, BOX, contrôle des centres par Shapely. Alpha multiplié, jamais étendu. |
| Caches | `CoastlineMask`, `MarineHTTP`, `BathymetryTileCache` | OSM HTTP persistant ≥7 jours ; masque RAM 512 entrées / 8 Mio ; raster LRU fournisseur 512 entrées, résultat final RAM 512 / 32 Mio et SQLite 128 Mio / TTL 24 h, version `marine-palette-3`. Single-flight, concurrence 8 et attente maximale 128 conservées. |
| API | `_render_bathymetry_tile`, `get_bathymetry_tile`, `map_tiles.py` | Raster totalement transparent : pas de masque téléchargé. Sinon application du masque avant cache final ; PNG public 24 h ; indisponibilité → 503, pas de succès vide fabriqué. Z autorisé ≤14. |
| Android | `MarineMapController.install`, `GlobeStyle.document` | Raster MIDDLE, opacité 1 dès Z5, source maxzoom 14, rééchantillonnage LINEAR ; océan BOTTOM bleu `#002D51`. Docks BOTTOM, ouvrages MIDDLE, hydrographie/balisage inchangés. |

La couleur sous un raster transparent n'est pas une profondeur mesurée. L'ancienne couleur de remplacement appartient pourtant aussi à la rampe bathymétrique, d'où une lecture visuelle trompeuse.

### XYZ et résolution

Pour le point indiqué : Z12 = 2115/1503 ; Z13 = 4231/3007 ; Z14 = 8462/6014 ; Z15 = 16924/12029 ; Z16 = 33848/24059. Les deux derniers sont des coordonnées théoriques : la source réelle reste limitée à Z14. Le point est très proche de la frontière sud et ouest de sa tuile Z14 ; il faut examiner les voisines.

Sept tuiles Z14 ont été téléchargées une fois et conservées localement : 8461/6014, 8462/6014, 8461/6015, 8462/6015, 8462/6013, 8463/6013 et 8463/6014. Les PNG source avec halo, après LUT, alpha avant masque, masque, résultat et composites sont dans `/tmp/nowave-coastal-audit/`. Les scripts et preuves compactes sont joints dans `artifacts/NW-220-coastal/`.

### Hypothèses classées

1. **A + D : couverture WMS transparente révélant le fond bleu nuit, amplifiée par le surzoom — confirmées dans les scénarios reproduits.** Les trous existent déjà dans le PNG source ; des pixels sans couverture restent situés dans l'eau OSM. Le masque n'invente pas ces trous. Le surzoom agrandit leur contour mais n'est pas leur origine.
2. **B : suppression incorrecte d'eau par le masque — non confirmée sur les sept tuiles.** Vérification indépendante des centres : aucun centre classé eau par l'union OSM n'est exclu. Des pixels source opaques sur terre OSM sont correctement supprimés ; cela ne prouve pas que toutes les côtes mondiales sont correctes.
3. **C : docks / relief / ordre de couches — contredite comme cause principale par le test Android.** Les bandes restent après désactivation temporaire des docks, ouvrages et relief ; elles se confondent avec l'océan uniforme lorsque le raster est masqué. Changer uniquement le fond sous le raster fait disparaître le bleu nuit aux mêmes endroits. Styles restaurés après expériences.
4. **E : LUT / flou / feather — non confirmée comme cause des bandes larges.** Alpha identique avant/après LUT, feather et masque uniquement réducteurs. Ils peuvent adoucir une bordure existante, sans fournir de données supplémentaires.

Sources primaires consultées : [maxzoom des sources Mapbox](https://docs.mapbox.com/style-spec/reference/sources/), [ordre de rendu et draping](https://docs.mapbox.com/help/troubleshooting/layer-rendering-order/), [EMODnet Bathymetry](https://emodnet.ec.europa.eu/en/bathymetry). La documentation confirme le surzoom et le possible réordonnancement en globe/terrain ; ce dernier n'est pas déduit des slots seuls. EMODnet décrit sa couche marine sans couverture terrestre et une grille de résolution finie ; les comparaisons de pixels restent la preuve locale utilisée.

## Audit 2 — contre-expertise avant correction

Passage distinct, effectué après l'audit 1 et avant tout changement du code applicatif. Il s'agit d'une seconde méthode par le même intervenant, pas d'une revue humaine indépendante.

- Relecture des opérations exactes de LUT, alpha prémultiplié, feather, crop, union des polygones et multiplication.
- Deuxième calcul à partir des géométries MVT brutes : union Shapely puis `contains_xy` sur les centres, sans réutiliser le masque PNG comme vérité géométrique.
- Comparaison pixel par pixel : alpha LUT exactement conservé, alpha final ≤ alpha avant masque ≤ alpha source sur chacune des sept tuiles.
- Aucun centre d'eau exclu : 0 sur les sept tuiles. Les pixels opaques supprimés correspondent aux centres terrestres de ces géométries.
- Pixels source totalement transparents dans l'eau (centres) : 122, 785, 702, 82, 731, 536, 0 respectivement dans l'ordre de `counteraudit.json`. Les comptages avec masque **entièrement** opaque, plus restrictifs, diffèrent légitimement (105, 585, 532, 69, 588, 434, 0).
- Les tests côtiers et EMODnet existants couvrent trous des îles, extents, frontières, pixels partiels, absence de données, retries, alpha et halo : **28 réussites avant correction**.
- Cache obsolète : le diagnostic fournisseur reconstruit les images sans cache du raster final. Le problème existe en amont et sur l'appareil ; aucune purge globale n'est justifiée.
- Un raster ou un masque vide doit rester vide : recolorer les pixels transparents, dilater le masque ou recopier les profondeurs voisines serait incorrect.
- Les quatre coins et le surzoom feront l'objet de régressions synthétiques / contrôles Android ; leur exhaustivité n'est pas prétendue à ce stade.

**Conclusion avant correction :** preuve suffisante pour corriger le choix sémantique du fond de remplacement. Aucune preuve ne justifie de modifier les géométries, l'alpha fournisseur, la LUT, les profondeurs, maxzoom ou les caches. Les limites de couverture légitimes doivent rester visibles et distinctes de la palette des profondeurs.

## Correctif et validations



### Cause retenue et alternatives

**Cause confirmée :** la couverture de la couche visuelle WMS près du littoral ne coïncide pas toujours avec la géométrie côtière vectorielle plus détaillée. Ses pixels sans couverture laissent apparaître le fond `#002D51`. Le surzoom rend les marches de cette couverture très visibles ; le fond a la même teinte qu'une partie profonde de la rampe. Ce n'est pas une nouvelle profondeur et ce n'est pas une ombre portée des quais.

L'absence de pixels **du produit coloré** ne démontre pas l'absence de toute mesure bathymétrique : les sondes vectorielles indépendantes peuvent exister au même endroit. Le libellé ajouté porte donc précisément sur la couverture colorée.

Alternatives écartées : dilater le masque OSM ou remplir les trous (invente une couverture), propager la teinte voisine (peut suggérer une profondeur), augmenter maxzoom (ne crée pas de données et dépasse le contrat actuel), changer les slots ou désactiver les docks (ne supprime pas la cause), lisser davantage l'alpha (étendrait ou masquerait la limite du fournisseur), changer globalement le bleu du globe (hors périmètre).

### Changement ciblé

- `mobile/lib/core/map/marine/marine_palette.dart` : teinte neutre `unmappedWater = #93ACB0`, distincte des couleurs de la rampe bathymétrique.
- `mobile/lib/core/map/globe_style.dart` : le remplissage **existant** `nowave-earth-ocean`, limité aux surfaces d'eau Mapbox, conserve le bleu du globe avant Z5 et emploie le gris dès Z5, sous le raster. Aucun nouveau layer, source ou téléchargement.
- `mobile/lib/core/map/marine/marine_map_controller.dart` : attribution native explicite « Fond gris : couverture bathymétrique colorée indisponible », lien vers EMODnet.
- Aucun fichier applicatif Python modifié. Ni RGB/alpha des PNG, ni masque, ni API, ni sondes, ni identifiants ne sont modifiés. Le gris est un fond sans échelle de profondeur ; les limites de couverture restent volontairement perceptibles.
- Version `marine-palette-3`, source maxzoom 14, minzoom de rendu 5, opacité 1, LINEAR, budgets, TTL et single-flight conservés. Aucune invalidation de cache requise : les octets de raster sont identiques.

### Tests ajoutés et adaptés

- `backend/tests/unit/test_coastal_raster_artifacts.py` : **12 cas** hors réseau. Côte et pixel partiel, quai rectiligne, jetée étroite, bassin avec entrée, île, polygones séparés, masque intégralement eau/terre, raster entièrement sans données, jonction de quatre tuiles, échantillonnage Z14→Z15/Z16. Le pipeline réel LUT→feather→crop→masque est appelé ; transparence, centres terrestres et RGB sont contrôlés.
- `mobile/test/core/map/globe_style_test.dart` : nouveau contrôle de composition avec le fond neutre, seuil Z5, géométrie eau, globe et terres préservés.
- `mobile/test/core/map/marine/marine_map_controller_test.dart` : attribution explicite, tout en conservant les contrôles maxzoom, cache, slot, opacité et réinstallation.
- `mobile/test/core/map/land_colors_test.dart` : l'ancienne assertion imposait le bleu à tous les zooms ; elle est remplacée par une évaluation indépendante de l'expression aux zooms 0.65, 4, 4.99, 5, 5.01, 12, 14 et 16. Les assertions relatives aux couleurs terrestres, classifications et opacités demeurent. Cette adaptation vérifie le comportement intentionnel du correctif, sans masquer une régression terrestre.

### Mesures complémentaires : dix tuiles et raccords

Les ouvrages de la photo ont ensuite été retrouvés vers **5.927° E / 43.109° N**. Le cadrage natif contrôlé emploie Z15.3 / cap 0° / inclinaison 63.75°. Les trois tuiles 8461/6012, 8462/6012, 8461/6013 complètent les sept premières ; les dix entrées brutes ont été jointes au commit initial ; la sélection actuelle et leur récupération sont décrites dans le README des preuves.

| Tuile Z14 | Pixels source alpha=0 | Pixels source alpha partiel | Sans couverture sur centre eau OSM | Centres eau exclus par masque |
| --- | ---: | ---: | ---: | ---: |
| 14/8461/6012 | 53008 | 0 | 1861 | 0 |
| 14/8461/6013 | 11972 | 0 | 1227 | 0 |
| 14/8461/6014 | 604 | 0 | 122 | 0 |
| 14/8461/6015 | 52140 | 0 | 785 | 0 |
| 14/8462/6012 | 65148 | 0 | 28 | 0 |
| 14/8462/6013 | 42012 | 0 | 702 | 0 |
| 14/8462/6014 | 112 | 0 | 82 | 0 |
| 14/8462/6015 | 41036 | 0 | 731 | 0 |
| 14/8463/6013 | 42880 | 0 | 536 | 0 |
| 14/8463/6014 | 0 | 0 | 0 | 0 |

Chaque tuile compte 65 536 pixels ; les nombres absolus permettent de recalculer les pourcentages. Les pixels transparents terrestres sont inclus dans la première colonne ; ils ne constituent pas tous une anomalie. Les colonnes « eau OSM » distinguent cette ambiguïté.

Sur les **13 couples adjacents** disponibles, comparaison des six pixels de halo communs : 1 572 pixels communs par couple, **0 différence d'alpha, 0 différence RGB sur les pixels valides des deux côtés**. Cela contredit une erreur de bbox / pas d'échantillonnage pour ces entrées et couvre plusieurs jonctions à quatre tuiles. Les tests synthétiques protègent également le halo et la grille globale. Ces mesures ne constituent pas une preuve pour tous les littoraux mondiaux.

Rejeu des dix tuiles à partir des PNG/MVT joints : succès, aucun accès réseau requis, mêmes invariants. Un premier appel isolé du diagnostic complémentaire avait levé `SystemError: null argument to internal routine` ; sa reprise séquentielle puis le rejeu complet ont réussi. La cause de cet incident de diagnostic n'est pas établie. Aucun test automatisé n'a présenté cet incident.

### Commandes exécutées et résultats exacts

Environnement existant : `.venv` Python **3.14.4**, Flutter **3.47.6** / Dart **3.13.5**. Il diffère du Python 3.12 / Flutter 3.47.5 décrits dans le README ; aucun environnement de développement ni verrou de dépendances n'a été modifié.

| Commande / passe | Résultat |
| --- | --- |
| `.venv/bin/python -m pytest backend/tests/unit/test_coastline.py backend/tests/unit/test_emodnet_bathymetry.py -q` avant correction | **28 passed**, 0.83 s |
| `.venv/bin/python -m pytest backend/tests/unit/test_coastal_raster_artifacts.py -q` | **12 passed**, 0.89 s |
| `flutter test --no-pub test/core/map/globe_style_test.dart test/core/map/marine/marine_map_controller_test.dart` | **11 passed** |
| `dart format --output=none --set-exit-if-changed lib test` final | **243 fichiers, 0 changé**, succès |
| `flutter analyze --no-pub` final | **No issues found**, 1.2 s |
| `flutter test --no-pub --reporter expanded`, première suite | **880 réussites, 1 échec** : assertion du fond bleu constant dans `land_colors_test.dart` ; diagnostic et adaptation expliqués ci-dessus |
| Même suite Flutter finale | **881 réussites, 0 échec**, environ 40 s |
| `.venv/bin/python -m pytest backend/tests -q`, première suite | **1006 passed, 2 skipped, 277 errors**, 35.85 s ; tous les errors sont dus à l'absence de `NOWAVE_TEST_ADMIN_URL`, 0 échec d'assertion |
| Suite backend complète avec PostGIS isolé, commande ci-dessous | **1283 passed, 2 skipped, 0 error/failure**, 42.22 s |
| `.venv/bin/ruff check backend/tests/unit/test_coastal_raster_artifacts.py` | **All checks passed** |
| `git diff --check` final | Succès |

Configuration de la passe complète PostGIS, réellement exécutée :

```sh
NOWAVE_TEST_PORT=55434 docker compose -p nowave-coastal-review -f compose.test.yaml up -d --build --wait --wait-timeout 90 database
NOWAVE_TEST_ADMIN_URL=postgresql://nowave_ci:ci-test-only@127.0.0.1:55434/nowave_ci .venv/bin/python -m pytest backend/tests -q --junitxml=/tmp/nowave-coastal-backend-final.xml
NOWAVE_TEST_PORT=55434 docker compose -p nowave-coastal-review -f compose.test.yaml down
```

Le conteneur était sain avant la suite ; la base de fixture avait un nom aléatoire, distinct de toute base utilisateur. Le conteneur et son réseau dédiés ont été retirés après validation. Aucun volume de développement ni service de production n'a été utilisé ou effacé.

La suite complète inclut les routes de tuiles, masques, bathymétrie, cache, 503 et les tests de base de données. Les deux skips restent : archive locale SHOM XYZ absente (hors sondes MVP), sonde Nginx non activée faute de `NOWAVE_TEST_NGINX`. Un avertissement existant Starlette recommande `httpx2` pour TestClient ; aucune mise à jour de dépendance hors périmètre.

Pas d'échec intermittent dans les suites : les deux échecs initiaux ont une cause déterminée (configuration PostGIS et contrat visuel modifié). Les résultats rouges initiaux sont conservés et ne sont pas remplacés par les résultats verts.

### Validation A — fonctionnelle sur Android réel

Appareil vérifié par `adb devices -l` et `flutter devices` : **LGN LX1 / Android 15 API 35 / AV5PJV6328H03108**. Version debug réelle `lib/main.dart`, API habituelle conservée, aucune simulation de GPS ni création de signalement.

Compilation/installation exécutées :

```sh
cd mobile
flutter run -d AV5PJV6328H03108 --dart-define-from-file=.env.json --no-pub --host-vmservice-port=8181
```

Build Gradle réussi en **7.7 s**, APK `build/app/outputs/flutter-apk/app-debug.apk`, installation en **5.4 s**. Réinstallation standard conservant les données ; aucune désinstallation ni effacement. L'application est laissée ouverte sur la zone de la photo.

Contrôles natifs réalisés :

- Avant/après au même centre **5.934167 / 43.085278**, Z15.3, cap 0°, pitch 45° : bandes sombres remplacées par le fond neutre ; jetée, terre, balisage et sondes visibles.
- Avant/après au même centre **5.927 / 43.109**, Z15.3, cap 0°, pitch 63.75° : quais, bassins et promontoire de la photo retrouvés ; bleu nuit supprimé, couverture inconnue encore discernable. Le cadrage est reproductible mais n'est pas présenté comme identique à la photographie utilisateur.
- Toulon **Z12, Z13, Z14, Z15, Z16** : pas de réapparition des bandes ; absence de sondes rendues à Z12, 99 à Z13 dans ce parcours ; marques et ports conservés.
- Seuils **Z4.99 et Z5** capturés : globe bleu conservé avant activation ; raster présent dès Z5. Les angles effectivement appliqués par le contrôleur globe sont consignés, et ne sont pas présentés comme le pitch demandé.
- Marseille **5.365 / 43.295**, Z12, Z15.3 et Z16 : second port examiné, terres et quais visibles sans fausse bande profonde.
- Déplacement et zooms rapprochés Z12→Z16→Z12, rotations et **glissement tactile ADB réel**, puis rechargement du style : éléments conservés. Le rendu final après reload retrouve la même expression de fond et les mêmes contrats de source.
- Contrôle offshore **5.9293 / 43.0637**, Z13→Z14→Z16→Z13 : **26 identifiants de courbes strictement identiques dans les quatre captures** ; respectivement 4, 2, 2, 4 entités de courbe majeure rendues dans les vues différentes. Sondes et libellés visibles ; aucun remplacement de profondeur par une couleur.
- Les **16 captures du parcours principal**, ainsi que les quatre captures offshore, se terminent avec compteur d'erreurs marines **0**, aucune requête active. Le passage continu et le reload ont été observés sans anomalie bloquante ; aucun benchmark FPS comparable avant/après n'est revendiqué.
- Menu d'attribution natif ouvert réellement : la mention du fond gris apparaît en premier et a été vérifiée visuellement et par la hiérarchie UI Android. Menu fermé ensuite.

Mesure complémentaire sRGB dans deux rectangles fixes :

| Région image | Rectangle (x0,y0,x1,y1) | Pixels sombres avant | Après |
| --- | --- | ---: | ---: |
| Jetée Saint-Mandrier | (300,650,470,930) | 9563 | 243 |
| Quais, zone photo | (0,280,620,530) | 10594 | 252 |

Critère explicite `R<60, G<105, B<140`, qui inclut certains symboles : les pixels restants ne sont donc pas présentés comme des artefacts résiduels. Inspection des grandes captures : les bandes bleu nuit ont disparu. À titre de contrôle, plusieurs pixels intérieurs terrestres non ambigus sont identiques avant/après, notamment (600,1180), (350,1200), (300,1300) dans la première paire et (245,400), (180,450) dans la seconde.

Les expériences « raster isolé natif sans import Standard » et « désactivation complète du fond importé » n'ont pas été réalisées : le cycle de rechargement de l'application réinstalle ses couches. Leur équivalent de **composite PNG isolé** sur fond neutre a été calculé séparément et n'est pas présenté comme une preuve de rendu natif. Les expériences natives réellement effectuées (raster masqué, docks/relief masqués, seul fond remplacé) suffisent à isoler le mécanisme confirmé.

### Validation B — technique, distincte de la passe fonctionnelle

Diff applicatif relu intégralement : **trois fichiers de production Flutter**, palette neutre / expression sur couche existante / attribution. Les autres modifications sont les tests et les preuves. Aucun refactoring général.

Comparaison des objets de style lus **auprès du moteur Android**, avant et après : sources racines identiques ; raster layer identique ; source raster identique après retrait du seul champ d'attribution. Cela contrôle concrètement minzoom/maxzoom, URL/version, cache, opacité, rééchantillonnage et slot. Le remplissage eau garde son slot BOTTOM, sa géométrie et son opacité ; seule sa couleur dépend du seuil Z5.

Effets de bord recherchés :

- Pas de nouvelles requêtes EMODnet, source vectorielle, couche supplémentaire, texture, boucle Dart par frame, traitement PNG, cache ou dépendance.
- Aucun changement de budgets RAM/disque, TTL, persistance, backoff, queue, retries ni sémantique empty/outside-coverage/degraded/partial/503.
- Aucun changement de `MarineZoom`, viewport, collisions des ports, fade des marques, couches de danger ni identifiants ; tests existants et contrôles natifs restent applicables.
- Le gris n'est pas dans la rampe des profondeurs ; la légende distingue le produit coloré manquant des sondes numériques qui peuvent exister indépendamment.
- Les centres terrestres restent exclus du raster ; aucun étalement de couverture n'est introduit. Une limite grisée en escalier peut rester visible : c'est la trace honnête d'une couverture absente, pas une profondeur reconstituée.
- Vérification finale des dossiers protégés : cinq fichiers et leurs empreintes identiques ; index Git vide ; branche autorisée conservée ; `dev` local toujours `c0361be7`.

**Concordance des deux validations :** la passe A prouve la disparition des bandes bleu nuit et le maintien des informations sur les cas Android testés ; la passe B confirme l'absence de modification des données et des mécanismes NW-220. Aucune divergence bloquante identifiée.

### Risques résiduels et verdict

- La couverture visuelle EMODnet garde ses limites et sa résolution ; elles ne sont pas comblées. Le fond gris est volontairement distinct, et non une nouvelle classe de profondeur.
- Les géométries OSM et Mapbox peuvent diverger ailleurs ; dix tuiles et deux ports ne prouvent pas tous les littoraux mondiaux.
- La validation native concerne Android ; iOS n'a pas été testé dans cet environnement.
- Pas de benchmark FPS avant/après ; le correctif ne rajoute aucune source, couche ni tâche par frame. Le comportement dynamique a été exercé sur appareil.
- Les deux tests optionnels SHOM/Nginx ignorés et la différence de versions locales/CI sont explicités ; les suites exécutées sont vertes.
- Le style Mapbox Standard reste un import externe ; le contrat réellement observé est joint, sans prétendre figer ses futures versions.

**Verdict : prêt pour revue, commit et PR après décision explicite de l'utilisateur**, sur le périmètre confirmé des bandes bleu nuit. La limite de couverture légitime reste visible en gris ; une exigence de supprimer aussi toute limite grisée nécessiterait d'autres données fournisseur, pas une extrapolation.

**État à la clôture de la validation :** aucun commit, ajout à l'index, push, PR, merge, changement de `dev`, modification Linear, déploiement ou modification de production réalisé.

**Autorisation ultérieure :** l'utilisateur a demandé le commit local de ce correctif et de ses validations. Cette autorisation ne couvre pas le push, la PR ou le déploiement.

## Preuves à ouvrir

- [Comparaison avant, zone photo](artifacts/NW-220-coastal/before-photo-area.png)
- [Comparaison après, zone photo](artifacts/NW-220-coastal/after-photo-area.png)
- [Pipeline de pixels et masque](artifacts/NW-220-coastal/pipeline-photo-area.png)
- [Planche des 16 captures Android — archive initiale](https://github.com/FBCIFY/NoWave/blob/f5e4527bd730dbda8ce6f716d941a32841f5f6f6/docs/test-reports/artifacts/NW-220-coastal/android-contact-sheet.png)
- [Message explicatif natif — archive initiale](https://github.com/FBCIFY/NoWave/blob/f5e4527bd730dbda8ce6f716d941a32841f5f6f6/docs/test-reports/artifacts/NW-220-coastal/after-attribution.png)
- [Inventaire et reproduction des preuves](artifacts/NW-220-coastal/README.md)
