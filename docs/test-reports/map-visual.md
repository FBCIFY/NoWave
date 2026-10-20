# Carte : rendu et ergonomie

Validation locale du 17 octobre 2026, sur l’application réelle NoWave.
Les quatre changements demandés sont réalisés : dégradé plus doux, bouées ×2,
badge Z et recentrage GPS ponctuel vers Z 15,5. Aucun déploiement distant.

## A. État Git initial

Branche `feature/marine-bathymetry`, HEAD `4fff447f` —
`feat(map): add bathymetry and port infrastructure layers`.
[Status, branche et cinq derniers commits avant toute modification](evidence/map-visual/git-initial.txt).

Le working tree contient déjà les travaux locaux bouées et multi-sources de la
mission précédente, y compris backend, tests, sources Flutter, icônes et rapports.
Ils constituent la référence et sont conservés. Le diff propre à cette mission
est fourni [séparément](evidence/map-visual/mission.diff), par rapport aux fichiers
locaux initiaux, y compris les fichiers qui étaient déjà non suivis.

## B. Analyse de l’existant

Fichiers lus : `map_screen.dart`, `MarineMapController`, `PortLayer`, `BuoyLayer`,
`MapConfig`, les overlays et commandes de carte, `LocationService`, `AccuracyHalo`,
les tests carte/localisation, ainsi que l’adapter EMODnet et ses tests.

La bathymétrie est un raster PNG EMODnet déjà recoloré par le backend, ajouté dans
le slot BOTTOM. Flutter ne possède pas les profondeurs brutes de cette image.
Une correction uniquement de la couleur de fond Mapbox ne pouvait donc pas
adoucir ses bleus existants. L’intervention backend se limite au traitement
chromatique de ces PNG, sans changer la requête WMS ou les données interrogées.

Les bouées utilisent les PNG Temaki existants avec un facteur de taille interpolé.
Les événements caméra fournissent le zoom. Les coordonnées GPS sont déjà affichées
en haut à gauche. Le bouton GPS activait un `FollowPuckViewportState` permanent ;
le flux GPS partagé alimente aussi coordonnées, curseur, halo et alertes.

## C. Changements réalisés

### Bathymétrie

Les six teintes conseillées sont retenues : `#E6F7FD`, `#D2F0FB`, `#B7E4F7`,
`#8FD0EE`, `#5CB3DF`, `#1E6FA8`. Le bleu final est moins sombre que l’ancien
`#0C2F50`. L’interpolation chromatique continue reste en place. Un lissage gaussien
léger de 0,65 pixel adoucit les ruptures du raster.

Le lissage utilise des couleurs prémultipliées par l’alpha, pour éviter que les
pixels transparents noirs ou blancs ne contaminent la côte. L’alpha source est
ensuite remis **exactement**, comme le vérifient les tests. Dimensions, emprise,
source EMODnet, paramètres WMS, cache et données bathymétriques restent inchangés.

Les couleurs sont des ancres du dégradé de la légende non linéaire existante ;
le PNG ne fournit pas de profondeur brute permettant d’affirmer des seuils exacts
0–5 / 5–15 / 15–30 mètres. Aucun mapping métrique artificiel n’est ajouté.
La texture et les reliefs du raster source restent perceptibles ; le traitement
n’invente pas de détail supplémentaire.

Le fond marin Mapbox est accordé au bleu côtier `#E6F7FD`. L’opacité du raster
passe progressivement de 0 à Z 4 à 1 à Z 7. Cela retire la limite rectangulaire
de couverture EMODnet de la vue globe, sans ajouter de données mondiales fictives.
À partir de Z 7, la bathymétrie conserve sa pleine opacité.

### Bouées

| Zoom | Avant | Après |
|---|---:|---:|
| 10 | 0,30 | 0,60 |
| 13 | 0,55 | 1,10 |
| 16 | 0,85 | 1,70 |
| 18 | 1,00 | 2,00 |

Même interpolation linéaire, mêmes images, couleurs, catégories, filtres, slot TOP,
ordre et collisions. À Z 18, le symbole passe de 24 à 48 points logiques.
Les collisions peuvent donc masquer davantage de bouées proches : c’est le
comportement existant conservé, sans autorisation d’overlap ajoutée.

### Badge Z

Petit badge clair à 90 % d’opacité, coins arrondis, sous les coordonnées.
Format `Z xx.x`, taille de texte 11. Les boutons du haut restent alignés sur le
haut du bloc de coordonnées. Les coordonnées et leur formatage ne sont pas remplacés.

### Bouton GPS

Au démarrage, le GPS met à jour le curseur et les coordonnées sans imposer de
suivi caméra. L’appui sur le bouton déclenche un vol vers la position réelle,
avec arrivée à **Z 15,5**, pitch 0 et orientation courante respectée (nord en mode nord).
La caméra reste libre après le vol. Le flux GPS continue d’actualiser curseur,
coordonnées et halo, sans déplacer la caméra.

## D. Détails techniques

- Taille : uniquement les quatre valeurs de `BuoyLayer.layer().iconSizeExpression`.
- Zoom : `onCameraChangeListener` transmet `cameraState.zoom` à un `ValueNotifier`.
  `MapZoomBadge` utilise un `ValueListenableBuilder`, ce qui évite de reconstruire
  toute la carte à chaque image de l’animation. Le notifier est libéré au dispose.
- GPS : `_locate(recenter: true)` récupère une position, place le viewport en
  `IdleViewportState`, attend la frame puis appelle `MapboxMap.flyTo`.
  Durée du vol : 2200 ms ; durée nulle si la réduction des animations est activée.
  L’animation peut être interrompue par un geste. `_isFollowing` reste faux.
- Les gardes mounted / éditeur de signalement / arrière-plan empêchent un recentrage
  tardif de déplacer la carte pendant une autre interaction.
- Traitement raster : uniquement `_NOWAVE_RAMP` et la fin de `recolor_bathymetry_png`.
  Pas de modification de provider, endpoint, schéma, sélection géographique ou fusion.

Six fichiers existants de code/tests modifiés et deux ajoutés :
`map_zoom_badge.dart` et `map_camera_test.dart`. Aucun changement de dépendances
ou de CI dans cette mission.

## E. Validation visuelle réelle

`flutter devices` a confirmé le LGN LX1 `AV5PJV6328H03108`, Android 15/API 35.
Application `fr.blueway.app`, vrai `lib/main.dart`, compte existant conservé.
Aucune application de démonstration et aucun GPS simulé sur l’appareil.

APK compilé avec `.env.json` et URLs locales de validation sur le port 8003,
accessible par ADB reverse. Les signalements continuent d’utiliser leur API réelle.
La configuration ignorée `.env.json` n’est pas modifiée. Le backend de production
n’est pas déployé par cette mission.

Chaque capture ci-dessous a réellement été ouverte et inspectée :

| Capture | Niveau / constat |
|---|---|
| [Avant : région](evidence/map-visual/before-regional-z10_8.png) | (6.12,42.96), Z 10,8 ; ancien contraste, petit balisage |
| [Après : région](evidence/map-visual/after-regional-z10_8.png) | Même caméra ; bleus plus doux, reliefs encore lisibles, bouées plus présentes |
| [Globe final](evidence/map-visual/globe-z1_5.png) | Z 1,5 ; pas de rectangle EMODnet, Z visible, halo conservé |
| [Vue locale](evidence/map-visual/after-local-z14.png) | (5.929,43.084), Z 14 ; côte et pontons lisibles, balisage jaune agrandi, reports/GPS présents |
| [Avant : bouées](evidence/map-visual/before-port-z17_5.png) | (5.9061,43.09235), Z 17,5 ; taille initiale |
| [Après : bouées](evidence/map-visual/after-port-z17_5.png) | Même caméra ; latérales environ deux fois plus grandes, couleurs et collisions conservées |
| [GPS : départ](evidence/map-visual/gps-departure.png) | Vol engagé depuis Z 1,5, capture à Z 1,8 |
| [GPS : transition](evidence/map-visual/gps-during.png) | Z 13,0 intermédiaire ; progression de caméra et du badge, chargement transitoire des tuiles |
| [GPS : arrivée](evidence/map-visual/gps-arrival.png) | Z 15,5, caméra centrée sur le fix GPS, environnement local et pontons visibles |
| [GPS : déplacement libre](evidence/map-visual/gps-free-after-pan.png) | Après glissement au doigt et trois nouveaux fixes GPS, la caméra reste décalée |

[Inspection native structurée](evidence/map-visual/native.json) et
[log ciblé](evidence/map-visual/native.log) :

- 116 événements de zoom pendant le test du vol, de Z 1,5 à Z 15,5 ; environ
  2,2 secondes de mouvement une fois le fix disponible. Ce n’est pas un benchmark FPS.
- Arrivée centrée sur le fix utilisé : écart caméra/fix inférieur à 1 m dans ce test.
  Cela mesure le centrage sur le fix, pas la précision géographique du téléphone.
- Après pan, trois nouvelles mesures GPS réelles arrivent ; la caméra reste au
  même centre décalé, à environ 167 m du fix courant, viewport Idle et following=false.
- Le badge correspond au zoom caméra : 1,5 / 10,8 / 14 / 15,5 / 17,5 et valeurs
  intermédiaires pendant l’animation.
- Après redémarrage de l’APK final et reload complet du style : une source par
  famille, une couche de bouées, reports installés, map_error et location_error null.
  L’expression d’opacité Z 4→7 et l’expression de taille ×2 sont lues dans Mapbox natif.
- Les PNG finaux sont repris après installation de l’APK contenant les dernières
  corrections. Le contrôle du fondu après reload ne repose pas sur une modification
  temporaire du style par le débogueur.

Les passages de zoom peuvent montrer le chargement normal des tuiles, visible dans
la capture intermédiaire du vol ; la vue d’arrivée se complète correctement.
Les images sont des captures Android, sans montage ou retouche.

## F. Tests et commandes

```sh
# Backend : changement de présentation des PNG uniquement
.venv/bin/ruff check backend
/tmp/nowave-marine/py312/bin/python -m pytest backend/tests/api backend/tests/unit -q

cd mobile
/home/palms/flutter/bin/dart format --output=none --set-exit-if-changed lib test
/home/palms/flutter/bin/flutter analyze
/home/palms/flutter/bin/flutter test
/home/palms/flutter/bin/flutter build apk --debug --dart-define-from-file=.env.json --dart-define=MARINE_API_BASE_URL=http://127.0.0.1:8003/ --dart-define=BATHYMETRY_TILES_URL=http://127.0.0.1:8003/api/v1/map/bathymetry/{z}/{x}/{y}.png

# Racine
 git diff --check
```

| Vérification | Résultat |
|---|---|
| Flutter ciblé GPS, badge et bouées | 12 succès |
| Flutter complet | **470 succès** |
| Flutter analyze | Aucun problème |
| Dart format | Aucun changement requis |
| APK debug avec configuration réelle | Construit et installé sur le LGN LX1 |
| Backend complet API/unit | **680 succès**, avertissement Starlette/httpx préexistant |
| Ruff | Réussi |
| Git diff --check | Réussi |

Les tests contrôlent le vol depuis le globe vers le vrai résultat du service GPS,
le zoom d’arrivée, l’absence de nouveau mouvement caméra après une mesure GPS,
la mise à jour du badge, l’interpolation ×2 et les collisions conservées.
Les tests raster vérifient transparence exacte, continuité, ordre clair/profond,
lissage et absence de contamination par les pixels sans données.
L’avertissement de migration Kotlin des plugins existants reste non bloquant.
Logs dans `evidence/map-visual/`, avec inventaire des captures et métadonnées APK.

## G. Première revue

Relecture du diff contre les fichiers locaux de départ, et des tests ciblés :
interpolation strictement ×2, couleur/catégorie et placement inchangés, alpha exact,
absence de fuite du notifier, caméra ponctuelle et séparation avec le flux GPS.
Les anciens tests qui plafonnaient la taille à ×1 sont adaptés à la décision ×2.

Les points corrigés ou protégés comprennent le lissage prémultiplié pour éviter
un liseré de couleur près des pixels transparents, la garde mounted des événements
caméra et les gardes contre un vol tardif pendant un signalement ou en arrière-plan.
Le test GPS vérifie aussi que la collecte initiale ne déclenche pas de vol imposé.
Aucune modification des ports, providers, reports ou du halo n’est nécessaire.

## H. Deuxième revue depuis les exigences

Second passage distinct de l’auteur depuis les quatre objectifs et leurs exclusions,
avec les captures réelles et les propriétés natives. Aucune revue humaine externe
n’est revendiquée.

Deux défauts visuels ont été constatés et corrigés :

- À très faible zoom, l’emprise régionale EMODnet formait un rectangle contrasté :
  fondu Z 4→7, sans changer la couverture ou les données. Contrôle après installation
  de l’APK final et reload, avec l’expression réellement lue dans le style.
- Ajouter le badge augmentait la hauteur du bloc et décalait verticalement les
  boutons du haut : alignement de la rangée sur son bord supérieur.

Recontrôle du recentrage depuis le globe, de son arrivée à Z 15,5 et de la liberté
après trois fixes GPS supplémentaires. Tous les PNG finaux ont été rouverts.
Les sources, styles portuaires, images de bouées, halo et travaux antérieurs sont
contrôlés inchangés par empreinte : [fichiers préservés](evidence/map-visual/preserved-files.json).
Les commandes Flutter complètes et la build ont été relancées après les dernières
corrections de code.

## I. État Git final

[Status, branche, historique, diff stat et diff check](evidence/map-visual/git-final.txt).
Le diff Git global inclut le travail multi-sources préexistant ; le
[diff de cette mission](evidence/map-visual/mission.diff) isole les huit fichiers
réellement concernés par le rendu, l’ergonomie et leurs tests.

Branche et HEAD inchangés. Aucun fichier local antérieur supprimé. Le halo jaune
n’a fait l’objet d’aucune modification. Aucun ajout de catégorie marine.

**AUCUN COMMIT. AUCUN PUSH. AUCUNE PR.**
Aucun reset destructif, restore destructif, rebase ou amend.
