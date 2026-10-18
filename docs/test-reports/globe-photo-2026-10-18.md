# NoWave — globe satellite et transition marine

Date : 18 octobre 2026. Réalisation et deux revues successives par le même agent ;
elles ne constituent pas deux revues indépendantes. Aucun commit, push ou PR.

## 1. Photographie retrouvée

Chemin exact : `/home/palms/NoWave/3d-rendering-planet-earth.jpg`.
Image de 4200 × 4200 pixels, effectivement ouverte avec l'outil de lecture
d'images avant toute modification du code, puis rouverte pour la seconde revue.
SHA-256 : `81c0aaa3fd9a08500200b5e0ec3766da72eb0242c0586da7160120c68853fdcb`.
Elle reste non suivie, inchangée, et n'est ni embarquée ni utilisée comme texture.

## 2. Analyse visuelle de la référence

Le diamètre terrestre représente environ 65 % de la largeur. L'Afrique domine
le centre, l'Europe occupe le haut. Le Sahara est très clair, beige et crème ;
l'Europe et l'Afrique centrale sont vertes. Les reliefs, les montagnes enneigées
et les côtes sont détaillés. Les mers côtières sont turquoise/cyan, avec des
variations sous-marines fortement accentuées ; les océans éloignés sont bleu
profond. Des bandes nuageuses blanches et des spirales semi-transparentes
traversent les océans et certains continents. La lumière vient du haut gauche,
avec une ombre marquée en bas à droite. Un liseré cyan très fin borde la sphère.
Le fond noir présente des étoiles nombreuses et des voiles bleus/violets.
Une petite Lune, environ 7 % du diamètre terrestre, apparaît en bas à droite.

## 3. État initial

Branche initiale : `feature/marine-bathymetry` ; HEAD : `df41dbfe`.
Seuls la référence et le répertoire SHOM étaient non suivis avant intervention.
Le code utilisait Standard, une projection globe, une eau claire et une
bathymétrie fondue de Z4 à Z7. Sa caméra déclarée visait Brest à Z7/pitch 60°.
L'APK effectivement présent montrait un globe vectoriel à Z1,5, des terres
claires, des noms de pays et un large halo blanc. Les deux constats sont
distincts : le code du dépôt et l'APK installé ne sont pas supposés identiques.
Preuve réelle : [avant](../../test-results/globe-photo-2026-10-18/before-app.png).

## 4. Architecture retenue

Flutter Mapbox `2.30.1`, Android natif `11.30.1`, vérifiés dans le SDK installé.
Un document JSON local importe **Mapbox Standard** sous l'identifiant `basemap`.
La projection globe, l'atmosphère et les couches de présentation appartiennent
au document racine. Aucune modification des couches privées de Standard.
Le SDK ne fournit pas de méthode Dart dédiée à l'atmosphère dans cette version :
la propriété documentée `fog` est définie dans le JSON du style.

Mapbox Satellite est ajouté comme source raster `mapbox://mapbox.satellite`.
Le style Standard Satellite existe dans le SDK, mais n'est pas substitué à
Standard : conserver Standard maintient son contrat `colorWater` et les slots
utilisés par toutes les couches marines. Aucun échange de styles pendant le zoom.
Les fichiers de présentation sont copiés dans le répertoire temporaire privé de
l'application pour donner aux deux SDK natifs des URL `file://` ordinaires.
Un échec de préparation garde Standard disponible.

Références techniques consultées : [imagerie Satellite](https://docs.mapbox.com/data/tilesets/reference/mapbox-satellite/),
[styles Flutter](https://docs.mapbox.com/flutter/maps/guides/styles/set-a-style/),
[atmosphère](https://docs.mapbox.com/style-spec/reference/fog/),
[chargement local natif](https://docs.mapbox.com/android/maps/api/11.2.0/mapbox-maps-android/com.mapbox.maps/-mapbox-map/load-style.html).

## 5. Fichiers concernés

- `mobile/lib/core/map/globe_style.dart` : style composé, géoréférencement, fondus, préparation locale.
- `mobile/lib/core/map/globe_presentation.dart` : libellés et frontières au seuil continental, réapplication après reload.
- `mobile/lib/core/map/map_config.dart`, `mobile/lib/main.dart` : préparation du style et repli Standard.
- `mobile/lib/features/map/presentation/map_screen.dart` : cadrage Afrique/Europe, rotation libre en latitude, présentation et Lune.
- `mobile/lib/features/map/presentation/widgets/globe_moon.dart` : Lune décorative sans interception tactile.
- `mobile/lib/core/map/marine/marine_map_controller.dart` : `minZoom: 4` pour éviter les requêtes bathymétriques invisibles au lancement.
- `mobile/pubspec.yaml` : déclaration des petits assets.
- `mobile/assets/globe/` : quatre quadrants nuages/ombre, Lune, crédits, provenance et SHA-256.
- `mobile/tool/prepare_globe_assets.py` : préparation géographique hors application, reproductible avec Pillow/numpy.
- Tests : `globe_style_test.dart`, `marine_map_controller_test.dart`, `map_camera_test.dart`, `buoy_source_error_test.dart`.
- Le présent rapport. Les preuves locales sont dans `test-results/globe-photo-2026-10-18/`, ignoré par Git comme auparavant.

Aucun fichier backend ni fichier `.env.json` modifié.

## 6. Continents et océans

Les continents proviennent de l'imagerie mondiale Mapbox, et non d'aplats ou
de la photographie de référence. Les couleurs naturelles, déserts, végétation,
reliefs et neige sont donc géographiques. Le relief du globe est essentiellement
visible dans l'imagerie ; aucun nouveau maillage montagneux mondial n'est ajouté.
Un voile bleu discret s'applique uniquement aux polygones `water` de Streets,
en réutilisant la source du masque de texture existant. Il ne recouvre pas les
terres et n'encode aucune profondeur. Le raster bathymétrique côtier reste intact.

## 7. Atmosphère

Atmosphère native cyan/bleu, fond spatial presque noir et étoiles natives.
Le halo initial trop large a été aminci après comparaison des captures réelles.
`horizon-blend` diminue avec le zoom. L'atmosphère reste liée au moteur et ne
consiste pas en une ellipse fixe superposée à l'écran.

## 8. Nuages

Mosaïque mondiale NASA Blue Marble de 2002, historique et sans météo en temps
réel. Reprojection géographique en quatre images Mercator 512 × 512, posées sur
quatre sources `image` natives. La rotation conserve leur ancrage géographique.
Les bandes et systèmes sont issus de données d'observation, pas d'un dessin
aléatoire. La couverture s'arrête à ±85,05113° comme la grille Mercator.
Les nuages sont drapés sur la surface : absence de volume, d'altitude et de
parallaxe atmosphérique. Leur opacité diminue jusqu'à zéro à Z5.

## 9. Éclairage

Un ombrage solaire doux, géoréférencé et fixe (direction artistique 35° O/35° N),
est composé avec les nuages. Il suit les coordonnées lorsque le globe tourne.
Ce n'est pas un terminateur astronomique calculé ni une indication de l'heure.
L'effet disparaît à Z5 afin de préserver la lecture marine. L'ombre reste moins
profonde et moins sculptée que celle de la référence, notamment au limbe inférieur.

## 10. Espace et Lune

Étoiles natives nombreuses, fond noir bleuté, sans animation ou timer ajouté.
Les voiles violets/nébuleuses détaillés de la photo ne sont pas reproduits.
La Lune utilise une projection de la texture NASA SVS/LRO en 128 × 128 pixels.
Elle est secondaire, placée hors du globe et des contrôles, enveloppée dans
`IgnorePointer` et exclue de la sémantique. Elle s'efface entre Z0,65 et Z1,1.
Sa position est strictement décorative.

## 11. Transitions

| Niveau | Comportement |
|---|---|
| Globe ~Z0,65 | Satellite opaque, nuages/ombre, atmosphère, étoiles et Lune ; libellés/frontières masqués. |
| Z4 | Satellite opaque, apparition des libellés/frontières ; bathymétrie encore transparente. |
| Z6 | Satellite à environ 1/3, bathymétrie à environ 2/3, nuages absents. |
| Z7 et plus | Satellite et voile océan retirés du rendu ; fond marin existant opaque. |
| Z9 | Carte marine normale, seuils GPS et signalements conservés. |
| Z12 | Isobathes/chiffres, sondes et aides selon les seuils existants. |
| Z14/Z16 | Détails côtiers et portuaires existants ; aucune décoration du globe au-dessus. |

Les opacités sont interpolées par Mapbox. Le passage des libellés au seuil Z4
est un changement de visibilité ; les fonds, eux, ne basculent pas brutalement.

## 12. Conservation de la cartographie marine

Bathymétrie, masque côtier, texture marine, isobathes, labels, sondes, dangers,
ports, bouées, aides fixes, signalements et GPS restent dans leurs contrôleurs
existants. Sources métier, filtres, données et seuils marins ne sont pas changés.
Les nouveaux fonds sont dans `bottom`, avant l'installation des fonds marins.
La même source `nowave-water-mask` est réutilisée, sans source dupliquée.
`API_BASE_URL` demeure l'unique base du backend. Aucune ancienne variable marine
n'est réintroduite. Les archives SHOM et la référence non suivies sont conservées.

## 13. Tests automatisés

Les commandes demandées ont été exécutées sur l'état final du code :

```text
dart format --output=none --set-exit-if-changed lib test : OK
flutter analyze --no-pub : No issues found
flutter test --no-pub : 526 tests passed
```

Tests ajoutés/étendus : document de style et vraie exportation des quatre PNG,
géoréférencement, unicité des identifiants, conservation de Standard, crédit NASA,
seuils et réapplication des libellés, reprise après échec, panne des sources
décoratives non bloquante, cadrage initial et contrainte permettant la rotation
verticale, absence de requêtes bathymétriques sous Z4.

Journaux : [format](../../test-results/globe-photo-2026-10-18/format.log),
[analyse](../../test-results/globe-photo-2026-10-18/analyze.log),
[tests](../../test-results/globe-photo-2026-10-18/tests.log).

## 14. Validation Android réelle

Appareil LGN LX1, `AV5PJV6328H03108`, utilisé après autorisation explicite.
Aucune suppression de données ni désinstallation. L'APK préalable a été sauvegardé
dans `/tmp/nowave-globe/original.apk` avant installation avec conservation des données.

Le backend public a renvoyé des 429 sur certaines tuiles et une requête manuelle
bathymétrique a renvoyé 404. Pour examiner les couches déjà développées, une
compilation temporaire a utilisé **uniquement** `API_BASE_URL=http://127.0.0.1:8005/`.
Un proxy local de validation, hors dépôt, orientait les sources marines publiques
vers le backend local existant sur 8004, et les autres routes vers le backend
public. Les premières demandes de signalements avaient été mal orientées dans
ce proxy et ont renvoyé 401 ; le routage de validation a été corrigé, sans changement
du code applicatif. Les signalements réels sont ensuite visibles sur les captures.
Le backend local a servi des tuiles réelles en 200 et a aussi subi des 503 de
fournisseurs, notamment pour certaines données américaines. Il ne s'agit pas de
données simulées. La version finale utilise à nouveau `.env.json`, sans override.

Captures ADB brutes, non retouchées, provenant de l'application :

- [globe final, configuration API habituelle](../../test-results/globe-photo-2026-10-18/final-globe.png)
- [crédits NASA, Mapbox et Maxar vérifiés dans le menu natif](../../test-results/globe-photo-2026-10-18/credits-nasa.png)
- [globe final, validation locale](../../test-results/globe-photo-2026-10-18/final-globe-local.png)
- [Méditerranée Z4](../../test-results/globe-photo-2026-10-18/med-z4.png)
- [Méditerranée Z6](../../test-results/globe-photo-2026-10-18/med-z6.png)
- [Toulon Z9](../../test-results/globe-photo-2026-10-18/toulon-z9.png)
- [Toulon Z12, isobathes, bouées, signalement](../../test-results/globe-photo-2026-10-18/toulon-z12.png)
- [Giens Z14, côte et profondeurs](../../test-results/globe-photo-2026-10-18/giens-z14.png)
- [port de Toulon Z16](../../test-results/globe-photo-2026-10-18/toulon-z16.png)
- [Cape Florida Z14, couverture fournisseur partielle](../../test-results/globe-photo-2026-10-18/miami-z14.png)
- [Pacifique](../../test-results/globe-photo-2026-10-18/pacific.png)
- [après rechargement du style](../../test-results/globe-photo-2026-10-18/reload-z12.png)
- [arrivée GPS](../../test-results/globe-photo-2026-10-18/gps-arrival.png)
- [déplacement libre après GPS](../../test-results/globe-photo-2026-10-18/gps-pan.png)
- [rotation tactile en latitude et longitude](../../test-results/globe-photo-2026-10-18/globe-vertical-rotation.png)

La caméra initiale mesurée est 15° E / 12° N, zoom effectif 0,652845 : le GPS
ne recentre pas l'ouverture. Après gestes verticaux/horizontaux, les centres
mesurés passent de (15°,12°) à (15°,61,64°), puis (70,39°,61,64°).
GPS : arrivée Z15,5, puis déplacement manuel stable sans reprise du suivi.
Rechargement et deux réinstallations de chaque contrôleur : identifiants uniques,
couches et données encore présentes. Aucun crash applicatif observé.

## 15. Comparaison avant/après et performances

Avant : terres vectorielles claires, pays omniprésents, eau pâle, large halo blanc.
Après : imagerie géographique, Sahara et végétation visibles, océans sombres,
nuages ancrés, halo cyan aminci, étoiles, petite Lune, puis cartographie marine
existante aux niveaux détaillés. La référence artistique n'est jamais affichée
en remplacement de Mapbox.

Les cinq PNG totalisent 980 097 octets ; les quatre quadrants représentent
environ 4 Mio de pixels RGBA, hors copies internes du moteur. Aucun shader ou
timer applicatif ajouté. Les textures sont préparées hors du thread UI ; les
continents sont demandés en tuiles selon la vue. Le satellite ne se dessine plus
à partir de Z7, les nuages à partir de Z5. Aucun jeu de données marin mondial
n'est embarqué dans l'APK.

Sur deux gestes tactiles en debug : 426 frames Android, 6 janky (1,41 %),
P90 10 ms, P95 12 ms, P99 15 ms ; relevé brut
[gfxinfo](../../test-results/globe-photo-2026-10-18/gfxinfo-debug.txt).
Il s'agit d'un échantillon court des frames Android, pas d'une garantie de
60 fps du moteur Mapbox ni d'un benchmark release. Des frames sautées sont
signalées pendant certains démarrages/hot restarts debug. La navigation testée
reste utilisable, sans mesure longue de consommation ou de chauffe.

## 16. Limites de fidélité et licences

- La Terre occupe environ 85–90 % de la largeur sur ce téléphone, contre 65 %
  dans la photo. Le SDK impose ici un minimum effectif de 0,652845 lié au format
  du viewport. La contrainte verticale par défaut a été retirée pour permettre
  une véritable rotation en latitude ; cela ne supprime pas ce minimum de zoom.
- La Méditerranée est plus sombre et moins turquoise que dans la référence.
  Les textures océaniques/reliefs de celle-ci sont fortement illustratifs ;
  aucune profondeur mondiale n'est fabriquée pour les imiter.
- Éclairage et nuages fixes, sans altitude nuageuse, ombres volumétriques ou
  terminateur astronomique. Ombre inférieure droite moins contrastée que la photo.
- Étoiles natives, sans nébuleuse violette détaillée. Lune décorative.
- Le curseur GPS et les signalements restent présents et peuvent recouvrir une
  petite partie du globe ; leur comportement métier est conservé.
- Recette iOS et benchmark de performance release non réalisés. Disponibilité
  complète des fournisseurs marins américains non confirmée à cause des 503.

Aucun nouveau fournisseur payant ni abonnement. L'imagerie Mapbox conserve les
conditions et coûts éventuels du compte existant, sans supposer une gratuité
illimitée : [tarification Flutter](https://docs.mapbox.com/flutter/maps/guides/pricing/).
Les dérivés NASA contiennent des données géographiques sans logo ni personne ;
les sources sont créditées dans le dépôt et dans les attributions de carte,
sans suggestion d'approbation NASA. Voir [conditions NASA](https://www.nasa.gov/nasa-brand-center/images-and-media/)
et `mobile/assets/globe/README.md` pour les URL, crédits et provenance.

## 17. Deux revues distinctes, même agent

**Première revue — implémentation et première capture réelle.** Vérification des
API dans le SDK installé, du style importé, de l'ordre des slots, des sources
partagées et des coûts mémoire. Comparaison avec l'image ouverte. Corrections :
halo initial excessif réduit ; cadrage racine explicité ; requêtes bathymétriques
invisibles empêchées sous Z4 ; Lune rapprochée du limbe sans gêner les contrôles.
Analyse et tests exécutés, sources décoratives indisponibles rendues non bloquantes.

**Seconde revue — reprise de la photographie et des critères.** Réouverture de
la photo originale, comparaison avec les captures globe et Z4/Z6/Z9/Z12/Z14/Z16,
contrôle des scènes Pacifique/Miami. Un blocage natif de latitude au zoom minimal
a été identifié et corrigé avec `ConstrainMode.NONE`, puis vérifié par gestes
réels dans les deux axes. Le contrôle du menu natif a montré que TileJSON
remplaçait les crédits NASA définis sur la source d'eau. Ces crédits utilisent
donc une petite source GeoJSON locale vide, sans requête ni géométrie, afin de
conserver les attributions des fournisseurs et les crédits des nouveaux assets.
Leur affichage a été confirmé dans le menu natif de l'APK final réinstallé.
Rechargement/réinstallations sans doublons, GPS et déplacement libre contrôlés.
Les écarts de cadrage, de turquoise, d'ombre et d'espace ont été conservés dans
ce rapport plutôt que présentés comme une reproduction photographique complète.

## 18. État Git final

Branche conservée : `feature/marine-bathymetry`. HEAD conservé : `df41dbfe`.
Modifications uniquement dans le frontend mobile, ses tests, ses assets/outils
et ce rapport. Index non modifié. Photo et archives SHOM toujours non suivies,
non ajoutées, non supprimées. Aucun commit, push, changement de branche ou PR.
Le listing exact est conservé dans
`test-results/globe-photo-2026-10-18/git-final.txt`.

Le réglage Android de veille pendant la connexion USB, temporairement activé
pour les captures, a été rétabli à sa valeur initiale `0` après reconnexion.
