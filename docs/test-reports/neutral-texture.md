# NoWave — points neutral et texture intermédiaire

Validation du 17 octobre 2026, sur l’application réelle et le LGN LX1 Android 15.
Les deux ajustements demandés sont réalisés. Aucun changement backend.

## État Git initial

Branche `feature/marine-bathymetry`, HEAD
`4fff447f feat(map): add bathymetry and port infrastructure layers`.
Les commandes `git status --short`, `git branch --show-current` et
`git log --oneline -5` ont été exécutées avant toute modification.
Leur sortie complète est conservée dans [git-initial.txt](evidence/neutral-texture/git-initial.txt).
Le working tree contenait déjà 11 fichiers suivis modifiés, ainsi que les fichiers
non suivis des missions précédentes ; il a servi de référence et a été conservé.

## Analyse et fichiers modifiés

Lecture préalable de `map_screen.dart`, `BuoyLayer`, `WaterTextureLayer`,
`MarineMapController`, du générateur d’icônes, des tests et de l’ordre des couches.

Le neutral était le PNG gris `nowave-buoy-neutral`, choisi par les expressions
existantes en cas de qualification absente, contradictoire ou non reconnue.
Toutes les images étaient enregistrées en 72 × 72 à densité 3. La texture est une
couche de motif sur le masque d’eau, dans `bottom`, avant les ports ; les bouées
restent dans `top`. L’ordre des couches est conservé.

Six fichiers préexistants modifiés, tous déjà non suivis au début de cette mission :

- `mobile/assets/icons/buoys/neutral.png` : petit disque sombre à la place de la silhouette grise.
- `mobile/assets/icons/buoys/README.md` : dimensions et nature du nouveau fallback.
- `mobile/tool/make_buoy_icons.py` : génération reproductible du disque.
- `mobile/lib/features/map/data/buoy_layer.dart` : dimensions natives du seul neutral.
- `mobile/lib/core/map/marine/water_texture_layer.dart` : valeurs d’opacité demandées.
- `mobile/test/features/map/data/buoy_layer_test.dart` : dimensions adaptées et contrôle des pixels du point.

Le [diff propre à cette mission](evidence/neutral-texture/mission.diff) compare au
working tree initial. Les nouveaux rapport et preuves sont ajoutés localement.

## Neutral : avant / après

Avant : silhouette de bouée grise, avec contour et petites vagues, dans un canevas
72 × 72 à densité 3, soit 24 pixels logiques avant interpolation.

Après : disque `#20262C`, sans contour ni décoration, dans un canevas 12 × 12 à
la même densité 3. Le canevas mesure 4 pixels logiques ; le disque mesure 3 pixels
logiques avant interpolation. Avec le zoom existant, son diamètre nominal est
1,8 px à z10, 3,3 px à z13, 5,1 px à z16 et 6 px à z18. Il reste visible et secondaire.
La boîte de collision du neutral devient également plus petite ; les options de
collision et les dimensions des bouées qualifiées restent inchangées.

Aucune modification des expressions de sélection, catégories, couleurs, cardinales,
latérales, eaux saines, dangers isolés ou marques spéciales. Le filtre conserve
exactement les cinq catégories déjà affichées : aucun objet supplémentaire ajouté.
Les onze PNG qualifiés restent identiques par SHA-256.

L’expression de taille est **strictement inchangée** :
`z10 → 0.60 ; z13 → 1.10 ; z16 → 1.70 ; z18 → 2.00`.
Les symboles qualifiés restent en 72 × 72 à densité 3. `iconAllowOverlap=false`,
`iconIgnorePlacement=false`, slot `top`, tri et alignement restent inchangés.
La lecture du style natif confirme ces valeurs et les dimensions 12/72.

La zone de contrôle comporte trois vraies latérales Open Waters, sans couleur ni
catégorie renseignées : `12864288941`, `12864288953`, `12864288950`.
Elles sont visibles comme petits points dans la même zone qui montrait les silhouettes
grises. Aucun ajout de données de démonstration ni modification de ces objets.

## Texture : valeurs exactes

| Zoom | Opacité finale | État précédent |
| --- | ---: | ---: |
| 0 | 6 % | 6 % |
| 6 | 9 % | 9 % |
| 11 | 10 % | 8 % |
| 14 | 5 % | 2,5 % |
| 16 | 1,5 % | 1,1 % par interpolation |
| 17 | 0,4 % | 0,4 % |
| 18 et plus | 0 % | 0 % |

Interpolation linéaire native entre les ancres. Courbe inchangée jusqu’à z6 et
à partir de z17 ; renforcement limité à l’intervalle intermédiaire. À z17,5,
l’opacité reste 0,2 %. Aucun changement du motif, de sa couleur, de sa génération,
de son cache, de son masque ou de son slot. Toujours statique, bleu sur bleu.

## Captures réellement inspectées

Appareil détecté par ADB : `AV5PJV6328H03108`, LGN LX1, Android 15/API 35.
APK construit avec la configuration réelle, installé avec `adb install -r`, lancé
à froid dans `fr.blueway.app`, sans effacer la session. Backend marin local existant
sur le port 8003 ; configuration des reports conservée. Aucun GPS simulé.
L’empreinte de l’APK installé correspond à celle du fichier construit localement.

Les huit PNG suivants ont été capturés par `adb exec-out screencap -p`, puis
**réellement ouverts et examinés**, sans retouche :

| Capture | Résultat observé |
| --- | --- |
| [before-neutral-z16.png](evidence/neutral-texture/before-neutral-z16.png) | Application précédente, centre 5,911°/43,0898°, z16 : silhouettes grises visibles. |
| [after-neutral-z16.png](evidence/neutral-texture/after-neutral-z16.png) | Même caméra : petits points sombres lisibles, sans silhouette, sans contour, nettement secondaires. |
| [before-texture-z11.png](evidence/neutral-texture/before-texture-z11.png) | Application précédente, Giens / Porquerolles, 6,12°/42,96°, z11, ancienne opacité 8 %. |
| [after-texture-z11.png](evidence/neutral-texture/after-texture-z11.png) | Même zone, 10 % : ondulations un peu plus perceptibles ; reliefs bathymétriques, côte, labels et bouées restent lisibles. |
| [before-texture-z14.png](evidence/neutral-texture/before-texture-z14.png) | Saint-Mandrier, 5,929°/43,084°, z14 : comparaison dans l’APK final, avec l’ancienne opacité de 2,5 % appliquée temporairement au style. |
| [after-texture-z14.png](evidence/neutral-texture/after-texture-z14.png) | Même caméra, opacité finale 5 % : traits plus perceptibles mais discrets ; jaunes, ouvrages et signalement conservent leur lisibilité. |
| [qualified-red-green-z17_5.png](evidence/neutral-texture/qualified-red-green-z17_5.png) | Port du Manteau, 5,9061°/43,09235°, z17,5, après rechargement réel du style : rouge/vert et taille ×2 conservés, eau presque unie. |
| [neutral-and-texture-z18.png](evidence/neutral-texture/neutral-and-texture-z18.png) | Centre 5,911052°/43,090438°, z18 : petit point toujours discret ; texture absente comme demandé. |

La courbe finale a été rétablie après le comparatif z14, puis le style Standard a
été rechargé entièrement : les valeurs finales et les dimensions du neutral ont
été revérifiées depuis le code réinstallé automatiquement. La validation finale
ne dépend donc pas d’un réglage temporaire du débogueur.

Preuves : [native.json](evidence/neutral-texture/native.json),
[native.log](evidence/neutral-texture/native.log),
[manifest des captures](evidence/neutral-texture/screenshots.json),
[appareil et APK](evidence/neutral-texture/device.json).
L’application a été laissée en vue locale libre à z14.

## Tests

Depuis `mobile`, avec `/home/palms/flutter/bin` :

| Commande | Résultat |
| --- | --- |
| `dart format --output=none --set-exit-if-changed lib test` | 162 fichiers, aucun changement requis |
| `flutter analyze` | Aucun problème |
| `flutter test test/features/map/data/buoy_layer_test.dart` | 10 tests réussis |
| `flutter test` | **471 tests réussis** |
| `flutter build apk --debug --dart-define-from-file=.env.json --dart-define=MARINE_API_BASE_URL=http://127.0.0.1:8003/ --dart-define=BATHYMETRY_TILES_URL=http://127.0.0.1:8003/api/v1/map/bathymetry/{z}/{x}/{y}.png` | APK construit, installé et testé |
| `git diff --check` | Réussi, sortie vide |

Contrôle complémentaire du générateur : régénération complète dans un dossier
temporaire, 12 PNG identiques aux assets finaux, dont les 11 qualifiés inchangés.
Les tests existants de sélection ambiguë, cardinales, IALA A/B, collisions, reload,
GPS, badge Z et ports passent. Aucun test backend requis : aucun changement backend.
L’avertissement Kotlin préexistant des plugins n’empêche pas la build.
Logs complets dans [le dossier de preuves](evidence/neutral-texture/).

## Revue 1

Relecture intégrale du diff relatif à l’état initial : seuls les six fichiers
listés changent. Vérification du PNG, des dimensions natives, de la densité,
de la conservation des onze variantes qualifiées, des expressions de sélection,
de la courbe de zoom et de l’ordre des couches. Le générateur et le PNG sont cohérents.

Aucune régression de code détectée. Un problème de validation a été corrigé :
une première prise destinée à z14 montrait encore z11, car le déplacement de caméra
du débogueur n’avait pas été appliqué. Elle a été remplacée par les captures z14
contrôlées ci-dessus. Le comparatif utilise l’ancienne opacité temporaire dans
l’APK final, puis la courbe complète est rétablie et le style rechargé.
Les versions finales de toutes les captures ont été ouvertes.

## Revue 2

Nouvelle passe par le même agent en repartant de la demande : neutral → point
sombre, absence de silhouette/décoration, taille secondaire, sélection inchangée,
bouées qualifiées inchangées et ×2 conservé, exactitude des sept ancres d’opacité,
absence d’animation et texture quasi invisible au port. Aucun écart supplémentaire.

Vérification automatisée : toute la partie `BuoyLayer.layer()` et les expressions
de qualification qui suivent sont identiques à l’état initial ; toute la méthode
de génération du motif d’eau est également identique. **749 autres fichiers
préexistants recensés sont préservés par SHA-256** (suivis ou non suivis, hors
fichiers ignorés), dont `map_screen.dart`, `MarineMapController`, tout le backend,
les ports, la logique multi-sources, le GPS, le badge Z, les reports et le halo jaune.
Voir [preserved-files.json](evidence/neutral-texture/preserved-files.json).

## État Git final

Sorties intégrales : [git-final.txt](evidence/neutral-texture/git-final.txt), contenant
`git status --short`, `git diff --stat`, `git diff --check`, branche et HEAD finaux.

Les six fichiers de cette mission étaient déjà non suivis : `git diff --stat`
ne les affiche donc pas. Son résultat global porte sur les modifications suivies
antérieures : 11 fichiers, 462 insertions, 122 suppressions. Aucun staging ajouté.
Le diff dédié et les empreintes documentent les changements effectifs de cette mission.
Branche et HEAD inchangés ; aucun travail antérieur supprimé.

**AUCUN COMMIT — AUCUN PUSH — AUCUNE PR.**
Aucun reset, restore, rebase ou amend.
