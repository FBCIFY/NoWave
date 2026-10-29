# Texture d’eau — validation du 17 octobre 2026

Mission terminée sur l’application réelle NoWave, téléphone LGN LX1 Android 15.
Texture statique bleu sur bleu, limitée aux surfaces d’eau ; intensité décroissante
aux zooms rapprochés. Aucun changement du backend pendant cette mission.

## A. État Git initial

- Branche : `feature/marine-bathymetry`.
- HEAD : `4fff447f feat(map): add bathymetry and port infrastructure layers`.
- Working tree déjà modifié par les missions précédentes : 11 fichiers suivis
  modifiés et les fichiers non suivis des couches marines, tests, icônes et rapports.
- Les trois commandes imposées ont été exécutées avant toute modification.
  Leurs sorties intégrales, dont `git status --short` et les cinq derniers commits,
  figurent dans [git-initial.txt](evidence/water-texture/git-initial.txt).
- Cet état local a servi de référence. Les modifications antérieures sont conservées.

## B. Analyse du rendu existant

Fichiers lus : `map_screen.dart`, `marine_map_controller.dart`, `port_layer.dart`,
`buoy_layer.dart`, `map_config.dart`, `pubspec.yaml`, tests de couches et de caméra.
Lecture des API Dart et du pont Android de `mapbox_maps_flutter 2.30.1` :
`FillLayer`, `VectorSource`, `StyleManager.addStyleImage`, `StyleController.kt`.

La carte utilise Mapbox Standard et une projection globe. Le contrôleur marin
règle la couleur de l’eau et ajoute le raster bathymétrique dans le slot `bottom`.
Les bassins portuaires utilisent également `bottom`, les ouvrages `middle`, les
bouées `top`. Les signalements sans slot et la position gardent leur priorité.
L’installation marine est déjà séquentielle et relancée à chaque chargement du style.

Le masque retenu utilise uniquement la géométrie `water` de Mapbox Streets v8,
qui comprend les océans, lacs et autres surfaces d’eau dès z0. Les sources internes
de Standard ne constituent pas une API publique à réutiliser par identifiant.
La source vectorielle explicite évite de dépendre de ces identifiants privés.
Références officielles : [Streets v8](https://docs.mapbox.com/data/tilesets/reference/mapbox-streets-v8/),
[slots Standard](https://docs.mapbox.com/mapbox-gl-js/guides/styles/work-with-layers/),
[fill-pattern](https://docs.mapbox.com/style-spec/reference/layers/#fill-pattern).

## C. Changements réalisés

- Nouveau `mobile/lib/core/map/marine/water_texture_layer.dart` : une source
  cartographique de masque, une image et une couche `FillLayer` décorative.
- `map_screen.dart` instancie cette couche, l’installe après la bathymétrie et avant
  les ports, et ignore ses erreurs de source comme les autres enrichissements
  facultatifs. Une panne de décoration laisse la carte et les commandes utilisables.
- Nouveau test de génération, concurrence, rechargement et reprise après panne.
  Le test existant de panne facultative couvre aussi la source de texture.
- Aucun autre fichier préexistant modifié. Le [diff de cette mission](evidence/water-texture/mission.diff)
  compare au working tree initial, et non à HEAD qui contient aussi les travaux antérieurs.

## D. Détails techniques

Image générée localement avec `dart:ui`, sans dépendance ni asset téléchargé :
512 × 512 pixels, 170 traits courts à ondulation sinusoïdale douce, longueurs,
positions, phases et épaisseurs irrégulières. Graine fixe : rendu identique à chaque
installation. Traits bleus `#377FA5` sur fond transparent, sans blanc ni noir.
Les traits traversant les bords sont recopiés de l’autre côté pour éviter une couture.
Le test vérifie que plus de 85 % des pixels restent entièrement transparents.

Le PNG est généré une seule fois par instance, conservé pour les changements de
style, puis enregistré avec `addStyleImage`. Une fois décodée, l’image occupe
1 Mio de pixels RGBA. Aucun timer, animation, widget superposé ou calcul à chaque
mouvement de caméra. Le GPU dessine le motif dans les polygones d’eau.

L’opacité du `FillLayer` utilise une interpolation linéaire native de `zoom` :

| Zoom | Opacité de couche |
| --- | ---: |
| 0 | 6 % |
| 6 | 9 % |
| 11 | 8 % |
| 14 | 2,5 % |
| 17 | 0,4 % |
| 18 et plus | 0 % |

À z1,5 : 6,75 % ; à z10,8 : 8,04 % ; à z17,5 : 0,2 %.
Les traits sont eux-mêmes partiellement transparents : leur contraste effectif
reste inférieur à cette opacité de couche. Cette atténuation donne surtout une
sensation de matière de loin et laisse le détail portuaire prioritaire.

Ordre : bathymétrie → texture (`bottom`) → bassins (`bottom`) → ouvrages (`middle`)
→ bouées (`top`) ; labels, reports et position restent lisibles au-dessus.
Les propriétés natives ont été interrogées sur l’APK installé, puis après un
rechargement réel de Standard : même expression, même motif, même slot.

La source `mapbox://mapbox.mapbox-streets-v8` apporte des requêtes vectorielles
cartographiques pour le masque ; elle utilise le jeton et le cache Mapbox existants.
Ce n’est pas un nouveau fournisseur de données marines. Si ses tuiles manquent,
seule la texture manque. Aucun endpoint ni flux métier n’est ajouté.

## E. Validation visuelle réelle

Détection par `flutter devices` et `adb devices -l` : LGN LX1,
`AV5PJV6328H03108`, Android 15/API 35. APK debug installé avec `adb install -r`,
lancement à froid de `fr.blueway.app/.MainActivity`, session utilisateur conservée.
L’application réelle utilise le backend marin local existant sur le port 8003 ;
la configuration des signalements reste celle de l’application. Aucun GPS simulé.
Les déplacements de caméra de contrôle sont effectués via le débogueur de cette
application, puis le bouton GPS et un déplacement au doigt sont testés sur l’appareil.

Tous les PNG ci-dessous ont été capturés avec `adb exec-out screencap -p`, puis
**réellement ouverts et examinés**. Les captures ne sont ni retouchées ni des maquettes.

| Capture | Scène / observations |
| --- | --- |
| [globe-z1_5.png](evidence/water-texture/globe-z1_5.png) | Globe, centre 0°/25°, z1,5. Matière extrêmement légère dans l’océan ; pas de grille ni de couture visible, frontières et labels lisibles. |
| [globe-without-texture-z1_5.png](evidence/water-texture/globe-without-texture-z1_5.png) | Même caméra, couche masquée temporairement : contrôle comparatif du faible effet sur le globe. |
| [regional-z10_8.png](evidence/water-texture/regional-z10_8.png) | Giens / Porquerolles, 6,12°/42,96°, z10,8. Traits fins perceptibles surtout dans l’eau claire, sans concurrencer les reliefs bathymétriques ou les bouées. |
| [regional-without-texture-z10_8.png](evidence/water-texture/regional-without-texture-z10_8.png) | Même caméra et même APK, décoration seule masquée : lecture des profondeurs conservée. |
| [local-z14.png](evidence/water-texture/local-z14.png) | Saint-Mandrier, 5,929°/43,084°, z14. Motif très discret ; digues, pontons, bouées jaunes, labels et signalement restent nets. |
| [port-z17_5.png](evidence/water-texture/port-z17_5.png) | Port du Manteau, 5,9061°/43,09235°, z17,5. Surface presque unie, bouées rouge/verte lisibles, pas de surcharge. |
| [port-pontoons-after-style-reload-z17.png](evidence/water-texture/port-pontoons-after-style-reload-z17.png) | Saint-Mandrier, 5,9326°/43,0835°, z17, après rechargement du style. Pontons et quai conservés, texture quasi imperceptible. |
| [gps-arrival-z15_5.png](evidence/water-texture/gps-arrival-z15_5.png) | Appui GPS depuis le globe : arrivée réelle à z15,5, position et signalements au-dessus du fond. |

Le compromis conserve volontairement un contraste très bas. La comparaison des
PNG confirme un effet effectif, même là où il est difficile à distinguer à petite
taille : dans une zone d’eau régionale de 580 × 580 pixels, environ 9 % des pixels
changent, de 1 à 8 niveaux RGB au maximum. Les grandes variations bleues, contours
bathymétriques, routes maritimes et éléments du fond Standard préexistaient ; ils
ne sont pas présentés comme de nouvelles ondulations.

Pas de répétition évidente ni d’artefact de bord observé sur les vues testées.
Les déplacements et le recentrage restent réactifs sur cet appareil. Aucun benchmark
FPS ou essai exhaustif de tous les appareils n’est revendiqué.

Contrôle GPS complémentaire : arrivée caméra 5,934062°/43,0851918°, fix réel
5,934062°/43,0851917°, `IdleViewportState`, `following=false`. Après un glissement
physique, la caméra reste à 5,9361393°/43,0851918°, distincte du fix GPS, et le suivi
reste désactivé. La carte a ensuite été laissée en vue locale libre à z14.

Preuves : [native.json](evidence/water-texture/native.json),
[native.log](evidence/water-texture/native.log),
[empreintes des captures](evidence/water-texture/screenshots.json),
[appareil et APK](evidence/water-texture/device.json).
L’empreinte de l’APK installé correspond à celle de l’APK construit localement.

## F. Tests et commandes

Depuis `mobile`, avec `/home/palms/flutter/bin` :

| Commande | Résultat final |
| --- | --- |
| `dart format --output=none --set-exit-if-changed lib test` | 162 fichiers, aucun changement requis |
| `flutter analyze` | Aucun problème |
| `flutter test test/core/map/marine/water_texture_layer_test.dart` | Test ciblé réussi, dont décodage PNG et reprise après panne |
| `flutter test` | **471 tests réussis** |
| `flutter build apk --debug --dart-define-from-file=.env.json --dart-define=MARINE_API_BASE_URL=http://127.0.0.1:8003/ --dart-define=BATHYMETRY_TILES_URL=http://127.0.0.1:8003/api/v1/map/bathymetry/{z}/{x}/{y}.png` | APK debug construit et installé |
| `git diff --check` | Réussi, sortie vide |

Le test de panne de source vérifie aussi que la carte et les boutons restent
accessibles. Les tests existants de GPS, badge Z, ports et bouées passent dans la
suite complète. Aucun test backend relancé : aucun changement backend dans cette mission.
Le warning de migration Kotlin des plugins préexistait et n’empêche pas la build.
Logs dans [le dossier de preuves](evidence/water-texture/).

## G. Première revue

Relecture du diff par rapport à l’état local initial : masque d’eau, ordre des
slots, transparence, génération unique, libération des objets `ui.Image` et
`ui.Picture`, installations concurrentes, rechargement et panne facultative.

Problèmes trouvés et corrigés :

1. Le pont Android du SDK décode un PNG, malgré le type `MbxImage` : le premier
   essai RGBA brut échouait lors de `addStyleImage` sur l’appareil. Passage au PNG
   encodé, ajout du décodage dans le test et nouvelle build/install à froid.
2. Typage trop large du faux `StyleManager` du nouveau test : annotation explicite
   `TextureStyle`, puis relance des tests et de l’analyse.

Contrôle réel ensuite : le motif est enregistré et dessiné ; comparaison avec la
couche masquée, quatre échelles, puis rechargement réel du style sans doublon ni
perte des ouvrages. Aucune autre correction visuelle nécessaire.

## H. Deuxième revue depuis les exigences

Seconde passe séparée menée par le même agent, en repartant de la demande et en
comparant l’intégralité du diff propre à cette mission, sans s’appuyer sur les
seules conclusions de la première revue.

Vérifications : ondulations fines, bleu sur bleu, pas de blanc/noir, aucun timer,
maximum d’opacité 9 %, atténuation continue jusqu’à zéro, masque exclusivement
sur l’eau, ordre sous les informations, indépendance vis-à-vis de la bathymétrie,
reprise après changement de style et panne non bloquante.

Les **728 autres fichiers préexistants recensés sont identiques par SHA-256**
à l’état initial (fichiers suivis ou non suivis, hors fichiers ignorés), dont tout le backend, les sources marines, les ports, les bouées et leurs
icônes, le contrôleur bathymétrique, le badge Z et le code du halo jaune.
Dans `map_screen.dart`, le diff se limite à l’import, l’instance, l’installation
et la panne de la texture ; GPS, coordonnées, navigation et reports sont inchangés.
Voir [preserved-files.json](evidence/water-texture/preserved-files.json).

Aucun écart supplémentaire trouvé. Aucune modification hors périmètre ajoutée.

## I. État Git final

Les sorties intégrales de `git status --short`, `git diff --stat` et
`git diff --check`, ainsi que la branche et le HEAD finaux, figurent dans
[git-final.txt](evidence/water-texture/git-final.txt).
Le statut et le diff Git globaux comprennent les travaux locaux antérieurs.
`git diff --stat` ne compte pas les fichiers non suivis ; le diff dédié de mission
inclut les deux nouveaux fichiers Dart et les deux intégrations modifiées.
Les nouveaux rapport et preuves sont conservés localement.

**AUCUN COMMIT — AUCUN PUSH — AUCUNE PR.**
Aucun reset, restore, rebase, amend ou suppression de travail local existant.
