# NoWave — finalisation de la cartographie marine — 19 octobre 2026

## État initial et périmètre

Branche : `feature/marine-bathymetry`. Dépôt : `FBCIFY/NoWave`.
HEAD : `11667a069aad0e485c99281e812cb9c68cb7a92e`.

Au départ : **27 fichiers suivis modifiés et 7 entrées non suivies**. Les ports
Z6, leurs tests, les quais, les feux et le fondu alpha de la mission précédente
étaient déjà présents. La correction locale `backend/alembic/env.py` était
également présente. Aucun de ces travaux n'a été réimplémenté ou écrasé.

L'état Git initial, le diff binaire et les empreintes de 746 fichiers sont
conservés dans `test-results/cartography-final-2026-10-19/` :
`git-initial.txt`, `initial.patch`, `baseline-hashes.json`.
La photographie, les archives SHOM, les `.env`, les secrets et les preuves
antérieures ont été conservés.

## Audit et cause démontrée des rectangles cyan

Documents consultés : `docs/architecture/marine-sources.md`,
`docs/architecture/emodnet-depths.md` et les rapports locaux du littoral,
du rendu marin et des ports. Le code actuel et les instances réellement
exécutées ont été inspectés, indépendamment de ces rapports.

Pipeline raster : WMS EMODnet `mean_multicolour` → PNG 262×262 avec marge →
recoloration NoWave/lissage prémultiplié existants → fondu alpha intérieur →
recadrage 256×256 → masque côtier OSM → endpoint PNG FastAPI →
`MarineMapController` → raster Mapbox sous les autres informations.
Les chiffres et isobathes utilisent leurs propres sources MVT.

Les instances Docker sont actives : backend 8000, PostgreSQL/PostGIS 55432,
web 8080. Le backend Uvicorn local 8004 fonctionne aussi, depuis le dossier
`backend`. Les deux `/health` retournent `ok`, les contrats OpenAPI contiennent
les routes attendues, et les deux instances servent les mêmes PNG de contrôle.
L'application Android emploie effectivement le **backend marin 8004** ; le
backend applicatif reste `https://api.no-wave.fr/`. Aucun proxy ni déploiement.

Les PNG WMS examinés ont un alpha binaire : Toulon, 53 008 pixels transparents
et 12 528 opaques ; Porquerolles, 55 632 transparents et 9 904 opaques sur 65 536.
Leur couverture est en marches d'escalier. Le traitement existant conserve ces
trous et les adoucit, mais leur contraste restait excessif à Z16–17 : les tuiles
Z14 sont alors agrandies. Le filtre raster est déjà linéaire. Les captures
décomposées montrent que le cyan vient du **fond Mapbox dans les trous alpha**,
et non d'une nouvelle profondeur, d'une texture de vagues ou d'un défaut de joint
entre tuiles entières.

La cause corrigeable principale est une **réinitialisation de configuration** :
`MarineMapController.install` applique déjà `colorWater = #E6F7FD`, mais
`GlobePresentation.synchronize` appelle le setter global
`setStyleImportConfigProperties` pour deux options de labels. Sur le SDK natif,
ce setter remplace la configuration de l'import ; les options omises reprennent
leur défaut. La couleur d'eau redevient `hsl(200, 100%, 80%)`, beaucoup plus cyan.

Preuve Android contrôlée : après le setter individuel, lecture native
`#E6F7FD` ; après la synchronisation du globe inchangée, lecture native
`hsl(200, 100%, 80%)`. Voir `config-reset-proof.json` et les captures
`diagnostic-base-only.png`, `diagnostic-raster.png`,
`diagnostic-water-reapplied.png`, `diagnostic-globe-reset.png`.
La simple réapplication de la couleur prévue élimine les rectangles cyan dans
la vue de Porquerolles contrôlée, sans toucher au PNG.

Références officielles : [configuration Standard et colorWater](https://docs.mapbox.com/map-styles/reference/standard/),
[setters de configuration Flutter](https://docs.mapbox.com/flutter/maps/api/latest/mapbox_maps_flutter/MapboxMap-class.html),
[maxzoom des sources et overzoom](https://docs.mapbox.com/style-spec/reference/sources/),
[rééchantillonnage raster](https://docs.mapbox.com/style-spec/reference/layers/#raster-resampling).

## Correction ciblée

`GlobePresentation` modifie désormais **chaque option de labels individuellement**.
Les seuils, valeurs, mécanismes de retry, sérialisation et reload sont conservés.
La couleur d'eau marine, le thème et l'éclairage restent en place, quel que soit
l'ordre des installations marines et du globe.

Aucune nouvelle couche, aucun changement backend, aucun préchargement
ou nouveau service, aucune dépendance ajoutée. Deux petits appels de configuration au
franchissement du seuil Z4 ou au reload remplacent un appel global ; aucun
traitement de pixels ni appel natif supplémentaire à chaque frame.

Le raster, sa palette, ses pixels valides, son alpha et ses zones NoData sont
strictement inchangés par cette mission. Le fond reste le véritable fond
cartographique, visible par transparence ; aucune profondeur supposée ni
surface artificielle au-dessus des données n'a été ajoutée.

## Couches, ports et aides préservés

| Élément | Source / ordre | Plage utile conservée |
|---|---|---|
| Globe, satellite, eau du globe, nuages NASA | Style natif Standard/globe, slot bottom | Décoration jusqu'à Z5–7 selon couche |
| Raster marin | EMODnet + masque OSM, bottom | Début Z4, opacité pleine Z7, source jusqu'à Z14 puis overzoom |
| Ports qualifiés | Open Waters/OSM, points `harbour`, top | Dès Z6, source Z6–14 puis overzoom |
| Infrastructures | IGN/NOAA/OSM ; docks bottom, ouvrages middle | Docks Z10, digues Z11,5, épis Z12,5, quais/pontons Z13 |
| Isobathes et chiffres | MVT hydrographiques, middle | Dès Z12, règles existantes inchangées |
| Dangers, bouées, aides fixes | MVT existants, top | Bouées/phares Z10, feux Z11/14, balises Z12/13 selon qualification |
| Signalements et GPS | Backend principal / position native | Comportement existant |

Les ports utilisent le provider et la famille déjà ajoutés : agrégation bornée
de tuiles Z8 aux niveaux Z6/Z7, géométrie ponctuelle représentative publiée,
identité MVT/provenance conservées, aucune transformation de quai en port.
La catégorie marina est utilisée seulement lorsqu'elle est renseignée.
Les ancres, interpolation de taille et collisions n'ont pas changé.

Les règles des aides fixes et bouées ont été relues : qualification et couleur
publiées, IALA A/B respectées lorsqu'elles sont connues, absence de déduction par
couleur seule. Aucun symbole ou attribut n'a été modifié dans cette mission.

## Tests et non-régression

Exécutés depuis le dépôt, avec les outils locaux :

```bash
.venv/bin/python -m pytest backend/tests -q
.venv/bin/ruff check backend
cd mobile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub --dart-define-from-file=.env.json \
  --dart-define=MARINE_API_BASE_URL=http://127.0.0.1:8004/
```

Pour Pytest, `NOWAVE_TEST_ADMIN_URL` est fourni au sous-processus sans impression
de secret, avec la base administrative **postgres** sur 55432. La fixture crée
et supprime sa propre base `nowave_test_<UUID>` ; la base de développement n'est
jamais passée aux tests. Aucun volume Docker supprimé, aucune base existante
réinitialisée. Le contrôle final ne trouve aucune base temporaire restante.
La limite de validation PostgreSQL signalée dans le rapport précédent est donc
levée pour cette passe.

| Contrôle final | Résultat |
|---|---|
| Backend complet, dont PostgreSQL/PostGIS | **1 154 réussites, 0 échec**, 1 avertissement Starlette/httpx ; 13,68 s |
| Flutter complet | **536 réussites, 0 échec** |
| Tests ciblés globe + marine | **9 réussites, 0 échec** |
| Formatage | 177 fichiers, 0 changement |
| Analyse Flutter | Aucun problème |
| Ruff backend | Conforme |
| APK debug | Construite, avis de migration Kotlin non bloquant |
| `git diff --check` | Sans erreur |

Le nouveau test protège la couleur d'eau, le thème et l'éclairage pendant
l'initialisation concurrente, les passages dans les deux sens et le reload.
Exécuté volontairement sur le code initial, il échoue ; avec le correctif,
il réussit. Cet échec de reproduction est conservé dans
`regression-before-fix.log`, distinct du résultat final entièrement réussi.
Aucun segmentation fault Pillow/Python n'a été observé pendant cette passe.

Les deux PNG de contrôle sont identiques octet par octet avant/après, avec
`Cache-Control: public, max-age=86400`. Les cinq réponses MVT valides de contrôle
(Toulon et Miami) sont également identiques, dont les sondes NOAA de Miami.
Une sixième requête, aux sondes EMODnet de Toulon, retourne 503 avant **et** après,
avec des timeouts/cooldowns amont dans les logs. Une réponse d'erreur ne constitue
pas une preuve de données de sondes disponibles. Le code et les données
hydrographiques, intégralement inchangés, sont aussi contrôlés par empreintes.

## Validation Android et comparaison

Appareil : LGN LX1 `AV5PJV6328H03108`, Android 15. Installation `adb install -r`
réussie, sans effacement des données. Redirection `adb reverse tcp:8004 tcp:8004`.
Captures avant/après aux mêmes coordonnées, zooms effectifs relus depuis le SDK.

Comparaisons ouvertes en pleine résolution : Toulon à `[5.932, 43.119]`, Z16 et
Z17 ; Porquerolles à `[6.201, 43.001]`, Z16. Les rectangles cyan parasites ont
disparu des vues corrigées, tandis que les pontons, quais, ancres et autres
objets restent à la même place. Le gain de netteté vient de la disparition du
fort contraste en blocs, sans flou supplémentaire ni modification du raster.
Voir [la planche avant/après](../../test-results/cartography-final-2026-10-19/comparison-before-after.jpg)
et les PNG originaux dans le même dossier.

Les **30 vues** de la matrice ont été capturées sur l'APK corrigée et ouvertes
en planche. Requêtes natives `queryRenderedFeatures`, limitées à la couche
`nowave-harbour-icons` :

| Vue | Z5,9 | Z6 | Z8 | Z10 | Z12 | Z14 |
|---|---:|---:|---:|---:|---:|---:|
| Toulon / rade | 0 | 31 | 13 | 2 | 1 | 0 |
| Marseille | 0 | 27 | 13 | 4 | 10 | 7 |
| Saint-Mandrier | 0 | 31 | 13 | 2 | 1 | 1 |
| Porquerolles | 0 | 32 | 14 | 3 | 1 | 1 |
| Miami | 0 | 38 | 10 | 5 | 9 | 9 |

Il s'agit de symboles dans la vue, régionale à Z6, et non du nombre de ports
d'une commune. Aucun identifiant répété dans ces résultats. Les variations
entre zooms reflètent cadrage et collisions ; le cadrage Toulon Z14 est dans
la rade, avec les ports hors de la zone retenue visible. La continuité en
overzoom est aussi vérifiée dans les captures portuaires rapprochées.
La lecture native de `colorWater` reste **#E6F7FD dans les 30 vues**.
Preuves : `native-harbour-queries.json`, `native-matrix-summary.json`,
`native-sources.json`, `final-contact.jpg` et les 30 PNG `final-*.png`.

Contrôles supplémentaires sur le même appareil : Porquerolles Z17 et entrée
du port Z15 ; Miami Z15 avec sondes et courbes visibles ; globe à Z0,6528
(contrainte native proche du Z0,65 demandé), Lune/atmosphère et nuages ;
traversée des nuages à Z5,3. Les captures ont été ouvertes.
Le vrai rechargement natif du style conserve la couleur d'eau et réinstalle
les sources sans identité de source répétée. Le bouton GPS recentre à Z15,5 ;
un déplacement manuel ensuite à Z12 reste conservé. Le profil distant renvoie
`UserProfile`, sans extraction du jeton. Preuves : `after-extra-checks.json`
et les captures `after-*.png`.

La balise SHOM `bcnlat:FR000002455300001` a été revérifiée dans la réponse
actuelle : latérale bâbord, rouge/blanc horizontal, support pile, IALA A.
Elle est réellement rendue à Z17, confirmée par son identité dans la requête
native et par la capture rapprochée ouverte ; les bouées rouges flottantes
voisines gardent leur dessin distinct. Preuves : `fixed-beacon-current.json`,
`aids-native-query.json`, `after-porquerolles-beacon-z17.png`.
Le réglage temporaire de maintien en veille USB a été restauré à sa valeur
initiale `0` et relu (`stay-awake-final.txt`). Le reverse 8004 reste disponible.

## Fichiers de cette mission

Modifiés par cette mission seulement :

- `mobile/lib/core/map/globe_presentation.dart`
- `mobile/test/core/map/globe_style_test.dart`

Créé : `docs/test-reports/cartography-final-2026-10-19.md`.
Les preuves et logs sont enregistrés dans le répertoire ignoré `test-results`
mentionné ci-dessus. Les autres changements Git appartiennent aux travaux
préexistants et sont conservés.

## Double vérification

1. **Fonctionnelle** : reproduction de la réinitialisation sur le SDK réel,
   comparaison des mêmes vues avant/après et contrôle de 30 placements natifs.
   Les blocs cyan parasites ont disparu des vues rapprochées contrôlées ; les
   profondeurs et géométries ne changent pas. Ports Z6, globe, nuages, reload,
   GPS et session ont été vérifiés sur l'APK installée. Les limites amont des
   sondes européennes restent explicitement signalées.
2. **Technique** : relecture du diff complet, du correctif et des fichiers
   de ports non suivis ; validation des suites complètes et du build ; contrôle
   des empreintes. **744 des 746 fichiers de référence sont inchangés** : seuls
   les deux fichiers Dart annoncés diffèrent. Le diff suivi préexistant,
   correction Alembic comprise, est identique octet par octet. Aucun changement
   de donnée, de route, de cache, d'URL, de seuil hydrographique ou d'asset.

Le correctif ne demande aucun traitement par frame ; aucun gain chiffré de FPS
n'est revendiqué. La source raster conserve sa résolution et son cache.

## Git final

Branche et HEAD inchangés. **29 fichiers suivis modifiés et 8 entrées non suivies**
au total, dont les travaux préexistants. Rien n'est indexé. Aucun fichier
supprimé. Les états exacts sont enregistrés dans `git-final.txt` et
`git-final-stat.txt` ; `git diff --check` est conforme. Les preuves générées
sont listées dans `evidence-manifest.json` et restent ignorées par Git.

## Limites

La résolution native EMODnet et son masque de couverture ne deviennent pas plus
fins : le correctif élimine le contraste cyan parasite en conservant la couleur
de fond prévue. Il n'augmente pas la précision du raster ni des profondeurs.
Des limites réelles de couverture peuvent rester visibles dans d'autres zones,
particulièrement lorsque la donnée valide adjacente est plus sombre.

La disponibilité réelle des sondes EMODnet européennes est dégradée par les
timeouts amont observés. Aucun changement de données, repli de fournisseur ou
allongement de timeout n'a été introduit pour dissimuler cette indisponibilité.

**Aucun commit, aucun push, aucune PR.**
