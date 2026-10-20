# Bouées NoWave — travail local du 16 octobre 2026

## État de la validation

Implémentation isolée, contrôles techniques et validation visuelle réalisés
sur le téléphone Android connecté, dans l'application normale (`lib/main.dart`),
avec sa session existante. Aucun contournement de l'authentification n'a été
utilisé pour les captures livrées. Les PNG ont tous été ouverts et analysés.

## Source et données

- TileJSON vérifié par HTTP : https://tiles.openwaters.io/seamap/tiles.json
- Tuiles XYZ : `https://tiles.openwaters.io/seamap/{z}/{x}/{y}.pbf`.
- Le TileJSON est la référence vérifiée pour le schéma, les zooms et l'URL
  XYZ. L'application utilise **les XYZ directement**, afin que le SDK conserve
  l'attribution locale avec le lien explicite CC BY 4.0. En utilisant `url`,
  le SDK natif remplaçait cette attribution par celle du TileJSON, sans ce lien.
- Source-layer : **`seamark`**, z2–14 ; ensemble du tileset : z0–14.
  Mapbox surzoome les données à partir de z14.
- Version annoncée lors du contrôle : Seamap 2026-09-28, données OSM 2026-09-21.
- Champs utilisés : `type`, `category`, `color`, `color_pattern`.
- Champs également vérifiés : `shape`, `name`, `topmark_shape`,
  `topmark_color`, `osm_id`, `cell_rank`. Ils ne servent pas au dessin.
  Aucun champ normalisé `topmark` n'est annoncé.
- Les couleurs multiples sont séparées par des **underscores** :
  `black_yellow_black`, `black_red_black`, `red_white`, etc.
- Filtre : géométrie ponctuelle et liste fermée `buoy_lateral`,
  `buoy_cardinal`, `buoy_isolated_danger`, `buoy_safe_water`,
  `buoy_special_purpose`. Aucun autre seamark, nom ou feu n'est rendu.
- Pas de filtre local sur `cell_rank` : la source réduit déjà les données
  aux faibles zooms. Le nombre de bouées dans une tuile change avec le zoom.

Le [relevé de vérification](evidence/buoys/source-verification.json) contient
les métadonnées utiles et un exemple décodé de chacun des cinq types, avec
l'URL exacte de sa tuile. Les cardinales et dangers isolés ont été confirmés
dans des tuiles bretonnes ; ils n'ont pas été trouvés dans l'échantillon toulonnais.

Les [tuiles sont CC BY 4.0](https://github.com/openwatersio/seamap#license),
les données OpenStreetMap sous-jacentes sont ODbL. Attribution intégrée à
la source : « © Open Waters: Seamap » avec lien vers le fournisseur et
la licence, et « © OpenStreetMap contributors » avec lien vers OSM.
Les contrôles d'attribution existants de Mapbox sont conservés.
Aucun code, sprite ou style complet d'Open Waters n'a été intégré.

## Sémantique

- Latérales : catégorie `port` + rouge et `starboard` + vert en IALA A.
  Une catégorie inconnue ou une contradiction donne un symbole gris.
- Si une latérale ne renseigne que `color=red` ou `green`, sa couleur connue
  est rendue sans en déduire ni exposer une catégorie bâbord/tribord.
- Chenal préféré : `preferred_channel_port` → vert/rouge/vert ;
  `preferred_channel_starboard` → rouge/vert/rouge, bandes horizontales.
- Cardinales : nord noir/jaune, est noir/jaune/noir, sud jaune/noir,
  ouest jaune/noir/jaune, seulement avec catégorie et motif concordants.
- Danger isolé : noir/rouge/noir horizontal ; eaux saines : rouge/blanc
  vertical ; marque spéciale : jaune.
- Donnée manquante, contradictoire ou motif non supporté : gris neutre.
  Aucun quadrant ni côté sûr n'est inventé à partir d'une couleur seule.
- Le contrôle de cohérence latérale est IALA A ; il ne prétend pas gérer
  les conventions de région B. Une combinaison incompatible reste neutre.

Anomalie réelle repérée à Giens : les objets OSM `10893768965` et suivants
contiennent notamment `category=port,color=green`, ou
`category=starboard,color=red`. Ces combinaisons ne sont pas converties
silencieusement en une indication de côté.

## Code et architecture

Créés :

- `mobile/lib/features/map/data/buoy_layer.dart` : source, images,
  expressions, installation idempotente et sérialisée.
- `mobile/assets/icons/buoys/` : SVG Temaki original, licence, provenance,
  et douze PNG locaux à densité 3.
- `mobile/tool/make_buoy_icons.py` : génération reproductible depuis le SVG local.
- Deux fichiers de tests : sémantique, assets, installation, reload,
  récupération après échec et panneau d'erreur de MapScreen.
- Ce rapport et ses preuves.

Modifiés : `map_screen.dart` (installation et exclusion des erreurs de
source facultative), `pubspec.yaml` (déclaration des assets).

Ordre : bathymétrie `BOTTOM`, ports `BOTTOM`/`MIDDLE`, bouées **`TOP`**,
reports et sélection sans slot. Cet ordre est indépendant de l'installation
asynchrone des reports. La [documentation Mapbox Flutter](https://docs.mapbox.com/flutter/maps/guides/styles/work-with-layers/)
confirme `TOP` au-dessus des POI, sous les labels Place/Transit, et les
couches sans slot au-dessus de l'ensemble du style.

Les deux blocs `try/catch` séparés des ports et des bouées empêchent un
échec d'installation de bloquer les autres couches. Les événements d'erreur
de la source `nowave-buoys` ne déclenchent pas le panneau global Mapbox.
L'installation des reports continue dans son contrôleur existant.
Après `onStyleLoadedListener`, les images/source/couche sont vérifiées sur
le style courant et réinstallées si absentes. Les images sont mises en cache
en mémoire ; aucune lecture d'asset par frame. Pas de timer ou de client HTTP
supplémentaire : Mapbox charge les tuiles, sans préchargement et avec un délai
de 0,25 s pendant les gestes.

Les fichiers de bathymétrie, ports, reports, GPS et configuration Mapbox
ne sont pas modifiés. Les captures montrent des labels lisibles ; certaines
bouées proches sont masquées par la collision aux petits zooms, puis se
séparent en se rapprochant. Aucun filtre de densité supplémentaire n'est ajouté.

## Icône

[Temaki `buoy`](https://github.com/rapideditor/temaki/blob/6d9ac860d1d615d4449aab049f630d25d036c19e/icons/buoy.svg),
projet officiel Rapid Editor, **CC0 1.0 Universal**.
Le SVG local a été comparé octet pour octet à ce commit officiel.
SHA-256 : `2d8afd52fb75d902ab1ec8bb7d948c356f95ac82c55c05fa40c4f9fe659b99b4`.

Variantes : silhouette Temaki conservée, halo blanc, fin contour sombre,
couleurs/bandes NoWave. La forme physique et les voyants propres à chaque
bouée ne sont pas reproduits. Mapbox utilise des images de style raster :
PNG 72×72, `addStyleImage`, pixel ratio 3, sans dépendance SVG en exécution.

## Zoom et collisions

Expression exacte :

```json
["interpolate", ["linear"], ["zoom"], 10, 0.30, 13, 0.55, 16, 0.85, 18, 1.0]
```

| Zoom | icon-size | Boîte logique de l'image |
| --- | --- | --- |
| 10 | 0,30 | 7,2 px |
| 11 | 0,3833 | 9,2 px |
| 13 | 0,55 | 13,2 px |
| 15 | 0,75 | 18 px |
| 16 | 0,85 | 20,4 px |
| 17 | 0,925 | 22,2 px |
| 18+ | 1,0 | 24 px |

Ce sont les dimensions calculées de la boîte, marge transparente comprise.
La courbe initiale a été conservée après observation : présence discrète à
z10,5/11, identification à z13 et symbole net à z16/17,5, sans taille excessive
par rapport aux routes/bâtiments. Sa partie rouge sur la même bouée OSM
`12888316271` mesure environ **13×15 px physiques à z13**, **20×24 à z16**,
**22×28 à z17,5**, hors halo/vague. Le [relevé de pixels](evidence/buoys/size-measurements.json)
documente la méthode et les limites de cette mesure. La progression observée
est cohérente avec l'interpolation, et ne justifie pas d'augmenter le maximum.

`minZoom=10`, `iconAllowOverlap=false`, `iconIgnorePlacement=false`,
`iconPadding=1`. Priorité de placement : danger isolé, cardinale, eaux saines,
latérale, spéciale. L'alignement sur le viewport préserve la lisibilité des
symboles quand la carte est inclinée ou tournée. Les reports conservent leur
overlap et leur ordre existants.

## Deux revues distinctes

**Revue 1 — diff et chemins d'exécution.** Schéma, types, images, slots,
ordre, style reload, duplication, erreur réseau, cache, attribution, licence
et périmètre contrôlés. Correction : `iconIgnorePlacement=true` permettait
des chevauchements entre symboles ; passage à `false` et assertion ajoutée.
Le premier analyze signalait aussi un import `dart:typed_data` inutile,
supprimé. Le faux StyleManager de test a été complété pour le setter des
propriétés de source appelé par le SDK.

**Revue 2 — reprise depuis les exigences et les données servies.** Relecture
de tous les fichiers ajoutés/modifiés, des PNG et de leur générateur, puis
nouvelle confrontation aux données méditerranéennes et bretonnes, à la
documentation de slots/collisions, au scénario de panne et au reload.
Pas de nouveau défaut de production trouvé. Ajout d'un test de non-régression
qui injecte les erreurs SOURCE/TILE des bouées et TILE des autres couches
facultatives, puis vérifie qu'une vraie erreur STYLE reste bloquante.

**Contrôle natif complémentaire après le visuel.** L'attribution du TileJSON
écrasait le lien CC BY explicite fourni au constructeur. Correction : XYZ
directes, mêmes données/zooms et attribution locale complète ; test renforcé,
rebuild, réinstallation, nouvelles captures et lecture de l'attribution native.
Ce changement ne touche ni les filtres, ni les couleurs, ni la courbe de zoom.

Ces revues sont deux passes de l'auteur ; aucune revue externe n'est revendiquée.

## Zone et captures

La rade de Toulon a été retenue à partir des tuiles, et non du seul nom du
port. La zone contient rouge/vert/jaune, des données incomplètes et la bouée
d'eaux saines OSM `1420666201` près de **5,95886 E / 43,08348 N**.
La série principale est centrée à **5,9061 E / 43,09235 N**, Port du Manteau.
Les latérales OSM `12888316271` (rouge) et `12888316272` (verte) y sont
confirmées à z16 par interrogation des features réellement rendues.

Appareil : **LGN-LX1**, Android API 35, **720×1610 px**, densité Android 320.
Même appareil, même résolution, centre principal constant, nord en haut,
pitch 0 sauf la capture dédiée à 45°. La caméra a été pilotée via le service
de débogage ; les coordonnées/zoom/pitch réels sont consignés dans
[device-validation.log](evidence/buoys/device-validation.log).

L'ancienne adresse locale de bathymétrie de `.env.json` n'était pas joignable
depuis le poste. Les captures utilisent le **même backend et le même endpoint**
de bathymétrie, via `adb reverse tcp:8000 tcp:8000` et une modification de
l'URL de source **en mémoire uniquement** vers `127.0.0.1:8000`. Le fichier
`.env.json` et le code de bathymétrie sont conservés. Cette adresse de test
nécessite la connexion ADB ; elle ne constitue pas une nouvelle configuration
persistante de l'application.

### PNG réellement ouverts et diagnostic

Les tailles ci-dessous sont celles de la boîte logique de l'image ; le dessin
occupe une partie de cette boîte. Aucun texte/sonde/phare/voyant nautique n'est
ajouté. Les objets sans données de couleur restent gris. Les noms de ports,
routes de ferry et POI visibles proviennent du fond Mapbox existant.

| PNG | Zoom / taille | Lecture, densité et collisions | Ports, bathymétrie, reports / anomalies |
| --- | --- | --- | --- |
| [Toulon z10,5](evidence/buoys/toulon-z10.5.png) | 10,5 / 8,2 px | Quelques bouées jaunes/rouges discrètes ; aucun nuage ; motifs trop petits pour être identifiés à cette échelle. | Labels/géographie lisibles ; bathymétrie très visible ; GPS/report beaucoup plus saillants. Ports peu détaillés à ce zoom. Aucun artefact de globe/pitch. |
| [Toulon z11](evidence/buoys/toulon-z11.png) | 11 / 9,2 px | Cinq bouées rendues lors du contrôle initial. Jaune, rouge et gris repérables ; paire centrale masquée par collision avec les labels. | Labels préservés, bathymétrie lisible ; GPS/report prioritaires. Pas de symbole tronqué ; le blanc/rouge n'est pas identifiable de loin. |
| [Toulon z12](evidence/buoys/toulon-z12.png) | 12 / 11,2 px | Huit bouées rendues lors du contrôle initial ; rouge/vert/jaune/gris distincts, sans amas. La paire centrale reste en collision avec le label du Manteau. | Ouvrages du port naval lisibles ; bathymétrie visible. Le GPS/report est partiellement hors cadre à droite à cause du centre choisi, pas d'une nouvelle couche. |
| [Toulon z13](evidence/buoys/toulon-z13.png) | 13 / 13,2 px | Latérales et fallback gris identifiables ; rouge centrale visible, verte proche encore masquée par collision. Autres vertes séparées au sud. | Labels et pontons visibles ; bathymétrie légère dans la rade. Pas de report dans ce champ. Aucun symbole coupé ou disproportionné. |
| [Toulon z16](evidence/buoys/toulon-z16.png) | 16 / 20,4 px | Deux bouées rouge/verte séparées et nettes aux positions attendues ; densité faible, aucune collision. | Port du Manteau, route et bâtiments restent dominants par leur emprise ; eau/bathymétrie en fond. Pas de report/cardinale ici. Aucun artefact. |
| [Toulon z17,5](evidence/buoys/toulon-z17.5.png) | 17,5 / 23,1 px | Même paire, dessin plus lisible et croissance limitée ; rouge/vert francs. Aucun chevauchement. | Une partie du littoral seulement reste dans le cadre ; les symboles ne deviennent pas énormes. Fond marin conservé. Pas de report dans ce champ. |
| [Pitch 45°](evidence/buoys/toulon-z16-pitch45.png) | 16 / 20,4 px | Paire nette, droite à l'écran malgré le pitch ; positions ancrées sur l'eau, pas d'étirement apparent. | Bâtiments 3D/route/label du port lisibles ; aucune occlusion anormale de la paire. Fond marin conservé. |
| [Eaux saines](evidence/buoys/toulon-safe-water-z17.png) | 17 / 22,2 px | Une bouée réelle au centre ; rouge et blanc vertical visibles, silhouette nette et mesurée. | Pas de port/report dans ce champ ; bathymétrie bleue et lignes/labels de ferry lisibles. Aucun amas ni symbole tronqué. |
| [Cardinale ouest](evidence/buoys/lorient-cardinal-west-z16.png) | 16 / 20,4 px | Jaune/noir/jaune visible sur la bouée OSM `1421434283` ; distincte des latérales et du danger isolé. | Centre **−3,3610654 / 47,7144827**. Eau et routes de ferry conservées ; aucun port/report dans le champ. Pas de collision ni artefact. |
| [Danger isolé](evidence/buoys/brest-isolated-danger-z16.png) | 16 / 20,4 px | Noir/rouge/noir visible ; une bouée réelle « Les Renards », OSM `9881781150`, de taille raisonnable. | Centre **−4,7914124 / 48,3500319**. Fond marin conservé ; aucun port/report dans le champ. Aucun symbole tronqué ou amas. |
| [Ports / reports après reload](evidence/buoys/toulon-port-reports-reload-z14.png) | 14 / 15,6 px | Bouées jaunes séparées, nettes et secondaires. Source/couche réinstallées après reload du vrai style Standard. | Centre **5,929 / 43,084**. Pontons, quais, labels et bathymétrie lisibles ; GPS et report orange nettement prioritaires. Pas d'anomalie nouvelle. |
| [Panne de source](evidence/buoys/toulon-source-outage-z14.png) | 14 / bouées absentes | Source de test sous le même ID, TileJSON local répondant réellement HTTP 404. Aucun symbole de bouée n'est rendu. | Même vue : ports, fond/bathymétrie, GPS et report restent visibles ; aucun panneau global d'erreur. État reports `installed`. Absence des bouées attendue. |
| [Source rétablie](evidence/buoys/toulon-source-recovered-z14.png) | 14 / 15,6 px | Source de test retirée, installation normale rappelée ; les jaunes reviennent sans doublons. | Même vue et même hiérarchie que la capture avant panne ; autres couches intactes. Une source et une couche de bouées confirmées nativement. |

### Comparaison et limites des observations

Les mêmes latérales sont comparables à z13, z16 et z17,5. La rouge passe d'un
corps de 13×15 à 20×24 puis 22×28 pixels physiques : progression graduelle,
pas de saut brutal ni de taille fixe. Le minimum z10,5/11 reste discret ; le
maximum z17,5 ne couvre pas une emprise excessive. Les cardinales et dangers
isolés ne sont pas présents dans les vues de Toulon : leur contrôle a nécessité
les deux vues bretonnes, choisies à partir des tuiles.

À z10,5, la source ne contient pas la paire centrale ; à z11/12, des labels
et collisions empêchent son affichage. Ces absences ne sont pas présentées
comme une observation de la même paire à tous les zooms. Le compromis retenu
préserve les labels, rend d'autres bouées comme présence discrète et affiche
la paire complète quand elle peut se séparer. Aucun classement `cell_rank`
supplémentaire ou masquage par catégorie n'est appliqué côté NoWave.

Les captures de port/report/panne complètent les vues centrées sur la paire,
qui n'ont pas toutes ces catégories dans leur champ. Le terrain et le globe
existants ne sont pas modifiés ; le pitch a été testé à 45° et la projection
native contrôlée. Aucun problème nouveau de netteté, halo tronqué, placement,
taille excessive, amas ou occultation des infrastructures n'a été observé.

Pas d'ajustement de taille après le visuel : la première courbe est conservée
sur la base de ces observations. L'itération finale corrige les crédits natifs,
puis reprend les captures avec l'APK final. Le test de panne est un test local
de la source facultative, pas une panne réelle revendiquée du fournisseur.

## Commandes et résultats

Depuis `mobile/` :

```sh
dart format --output=none --set-exit-if-changed lib/features/map/data/buoy_layer.dart lib/features/map/presentation/map_screen.dart test/features/map/data/buoy_layer_test.dart test/features/map/presentation/buoy_source_error_test.dart
flutter analyze --no-pub
flutter test --no-pub
flutter test --no-pub test/features/map test/core/map test/integration/map_publication_test.dart
flutter build apk --debug --no-pub --dart-define-from-file=.env.json
```

Depuis la racine : `git diff --check` et inspection du diff, du status et
des nouveaux fichiers non suivis. Aucun commit, push, PR, rebase ou reset.

Les journaux sont dans [evidence/buoys](evidence/buoys/).

- Analyze final : **No issues found**.
- Suite complète finale : **463 tests réussis**.
- Deuxième passe ciblée : **51 tests réussis**.
- APK debug : compilation réussie après corrections.
- `git diff --check` : aucune erreur.

## Git final

Branche : `feature/marine-bathymetry`. Au départ : arbre propre, HEAD
`4fff447f`. À la fin : même HEAD, même historique ; deux fichiers suivis
modifiés (`map_screen.dart`, `pubspec.yaml`) et les nouveaux fichiers bouées,
tests, assets, générateur, rapport et preuves non suivis. Aucun fichier existant
hors de ce périmètre n'est modifié. `git diff --stat` décrit uniquement les
deux fichiers suivis : 16 insertions, 1 suppression. Les nouveaux fichiers ne
sont pas ajoutés à l'index. Le contrôle des espaces a aussi été effectué sur
les nouveaux fichiers texte.

**Aucun commit, aucun amend, aucun push, aucune PR, aucune modification de
branche distante, aucun reset/rebase et aucune suppression de travail existant.**
