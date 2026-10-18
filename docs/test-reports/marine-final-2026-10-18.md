# Cartographie marine — correction locale du 18 octobre 2026

Le dégradé bleu est rétabli sur le LGN LX1 dans les zones couvertes. Les
isobathes françaises portent leurs valeurs aux zooms régionaux ; les balises
fixes à bandes rouges/blanches et vertes/blanches sont maintenant reconnues.
Conformément à la réponse utilisateur : **EMODnet en Europe, sondes NOAA aux
États-Unis**. Les levés SHOM archivés restent conservés, hors chiffres du MVP.

La validation globale reste **partielle** : pas de raster de profondeur dans
le secteur de Miami testé, pas de sondes françaises originales supplémentaires
dans le flux choisi, incidents réseau NOAA observés. Deux passes de revue
distinctes ont été effectuées par le même agent ; aucun relecteur extérieur
indépendant n'est revendiqué.

Les [preuves Android et journaux](../../test-results/marine-final-2026-10-18/)
sont conservés localement dans un dossier ignoré par Git. Les captures finales
liées ici ont réellement été ouvertes et examinées. Elles proviennent de
`adb exec-out screencap -p` sur le téléphone physique, sans montage du rendu.

## A. État Git initial

- Branche : `feature/marine-bathymetry`.
- HEAD : `20437348` — `feat(map): add fixed aids lighthouses and marine lights`.
- 698 fichiers suivis ou non suivis, hors fichiers ignorés ; 16 fichiers suivis
  modifiés et 28 fichiers non suivis, soit 44 fichiers locaux préexistants.
- Aucun changement indexé. Les fichiers SHOM, les preuves antérieures et toutes
  les modifications hydrographiques ont été conservés.

Sauvegarde extérieure au dépôt :
`/home/palms/nowave-snapshots/marine-final-20261018T122354Z/`.
Elle contient les empreintes SHA256 des 698 fichiers, les copies initiales des
fichiers concernés, le statut détaillé, les diffs et la configuration locale
initiale protégée. Le diff propre à cette mission est `task-delta.patch`.

L'état était plus avancé que les 737/480 tests cités dans la demande : le
[rapport EMODnet précédent](emodnet-depths-2024.md) annonçait 819 tests backend
et 485 Flutter. Le retrait des losanges et l'essentiel des labels d'isobathes
étaient déjà présents dans la correction du 17 octobre. Ils ont été conservés
et revérifiés, sans recommencer l'implémentation.

## B. Diagnostic bathymétrique

**Cause exacte : URL raster périmée dans l'APK installée.** L'inspection native
avant modification montre `nowave-bathymetry` configurée sur
`http://10.111.202.118:8000/api/v1/map/bathymetry/{z}/{x}/{y}.png`, alors que les
MVT utilisent déjà le backend local 8004. Les logs du téléphone montraient des
timeouts de tuiles raster de 60 secondes. Le backend local et ses PNG étaient
fonctionnels. [Configuration native avant](../../test-results/marine-final-2026-10-18/before-native-sources.json).

La seule clé modifiée dans le fichier ignoré `mobile/.env.json` est
`BATHYMETRY_TILES_URL`, désormais
`http://127.0.0.1:8004/api/v1/map/bathymetry/{z}/{x}/{y}.png`. Les autres valeurs
sont identiques à la sauvegarde ; aucun secret n'est reproduit ici. Le build
final fournit également cette URL explicitement par dart-define.

Analyse réelle de PNG 256×256 reçus avec HTTP 200 :

| Zone / tuile XYZ | Octets | Couleurs RGB non transparentes | Alpha min…max |
|---|---:|---:|---|
| Large, 12/2115/1504 | 33 293 | 293 | 0…255 |
| Large, 14/8461/6017 | 3 866 | 38 | 255…255 |
| Port, 12/2115/1503 | 25 246 | 287 | 0…255 |
| Port, 14/8461/6013 | 6 207 | 59 | 0…255 |

[Mesures pixels](../../test-results/marine-final-2026-10-18/raster-backend.json).
La palette existante `#E6F7FD`, `#D2F0FB`, `#B7E4F7`, `#8FD0EE`, `#5CB3DF`,
`#1E6FA8` et l'adaptateur raster backend sont inchangés. Aucun nombre ni contour
n'est extrait des couleurs. La transparence terrestre/nodata est préservée.

La source raster garde `maxzoom=14`, son layer n'a pas de maxzoom : Mapbox
surzoome les PNG Z14 à Z14.8, Z15.8 et Z17. L'opacité vaut 1 dès Z7, slot BOTTOM.
La texture BOTTOM est installée après le raster, avec son opacité discrète
existante ; les contours MIDDLE restent au-dessus. Aucun changement des slots,
de la palette ou de l'ordre n'était nécessaire pour corriger la panne d'URL.

Preuves visuelles : [Vauban avant](../../test-results/marine-final-2026-10-18/before-vauban-z14.8.png),
[Vauban après Z14.8](../../test-results/marine-final-2026-10-18/final-vauban-z14.8.png),
[large Z12](../../test-results/marine-final-2026-10-18/final-offshore-z12.png),
[large Z14](../../test-results/marine-final-2026-10-18/final-offshore-z14.png),
[large Z15.8](../../test-results/marine-final-2026-10-18/final-offshore-z15.8.png),
[large Z17](../../test-results/marine-final-2026-10-18/final-offshore-z17.png).
La nuance locale portuaire est naturellement plus faible qu'au large.

Le rechargement réel du même style, suivi de deux réinstallations des couches,
conserve des IDs uniques et rétablit le raster :
[preuve native](../../test-results/marine-final-2026-10-18/reload-proof.json),
[capture après rechargement](../../test-results/marine-final-2026-10-18/final-after-reload-z12.png).

## C. Labels d'isobathes

Le mécanisme existant utilise `depth_label` issu de la profondeur publiée,
`symbol-placement=line`, rotation MAP, texte à l'endroit, halo clair 0,6 px,
collisions natives actives. Les valeurs NOAA décimales ne sont pas arrondies
systématiquement. Les labels des courbes sont distincts des chiffres ponctuels.

| Zoom | Taille du texte | Espacement des répétitions |
|---|---:|---:|
| 12 | 10,5 px | 160 px |
| 13 | 11 px | 160 px |
| 14 | 11,5 px | 160 px |
| 15 | 12 px | 176 px |
| 16 | 12,5 px | 192 px |
| 17 | 13 px | 208 px |
| 18+ | 13,5 px, plafonné | 224 px, plafonné |

Les expressions interpolent linéairement. La taille était déjà correcte ;
l'espacement, auparavant constant, dépend maintenant du zoom. Un essai à
128/144 px supprimait la valeur 50 par collisions dans le cadrage réel ;
160 px conserve deux inscriptions 50 à Z12 et une inscription 100. Le réglage
final a été recompilé et revérifié nativement dans l'APK finale.
[Expressions natives finales](../../test-results/marine-final-2026-10-18/review2-native-style.json).

Le contrôle existant `feature-state.label_visible` autorise une ligne seulement
si Mapbox a placé un label de cet ID dans le viewport ; mouvement, changement
de style et réponse périmée invalident le placement précédent. Il ne force pas
le texte au-dessus des aides. Les fragments trop courts ou entièrement exclus
par collision restent masqués. Cela peut retirer une courbe, jamais inventer
sa profondeur.

Au centre 5.93°E, 43.06°N :

| Zoom | Résultats labels natifs | Fragments de lignes visibles | Chiffres ponctuels |
|---|---:|---:|---:|
| 11.9 | 0 | 0 | 0 |
| 12 | 5 | 5 | 4 |
| 13 | 4 | 4 | 4 |
| 14 | 2 | 2 | 20 |
| 15.8 | 0 | 0 | 8 |
| 17 | 0 | 0 | 6 |

À Z12, les attributs donnent 50, 50, 100, 200 et 500 mètres. Certaines valeurs
de bordure sont partiellement couvertes par l'interface ; 50/100/200 sont
lisibles sur les courbes. Les comptages sont des résultats natifs et peuvent
inclure des fragments de tuiles, pas autant de courbes physiques distinctes.
Toutes les lignes effectivement visibles des 17 cadrages contrôlés ont un ID
possédant un label placé. Une boîte de label Miami Z12 intersecte le bord droit
alors que sa géométrie est hors écran : ce résultat natif marginal n'est pas
une profondeur sans géométrie.

[Z11.9](../../test-results/marine-final-2026-10-18/final-offshore-z11.9.png),
[Z12 avec valeurs](../../test-results/marine-final-2026-10-18/final-offshore-z12.png),
[Z13](../../test-results/marine-final-2026-10-18/final-offshore-z13.png),
[attributs natifs Z12](../../test-results/marine-final-2026-10-18/final-offshore-z12-rendered.json).

## D. Précision des contours français

Le jeu vectoriel reste EMODnet Contours 2022, dérivé du DTM et généralisé au
1:500 000. Il ne correspond ni au raster courant ni aux cellules numériques
2024. La stratégie existante est conservée : Z12–13, opacité principale 0,72 /
secondaire 0,48 ; Z14, 0,32 / 0,22 ; lignes et labels exclus à partir de Z15.
Une telle généralisation ne permet pas d'interpréter un chenal ou un bassin à
fort zoom. Les cadrages Z14 puis Z15.8/Z17 confirment cette limite visuellement.

La restriction porte sur `derivation=published_dtm_contour_2022`, pas sur le nom
du fournisseur dans Flutter. Elle ne retire ni le raster bleu, ni les cellules
EMODnet 2024, ni les contours ENC NOAA détaillés. Aucun contour portuaire
français plus précis n'est fabriqué pour prendre le relais.

## E. Profondeurs portuaires

### Provenance exacte du chiffre 7

La Tasse et Bérouard se trouve à **La Ciotat**, pas à Toulon ; le lieu est
confirmé par [l'office de tourisme](https://www.destinationlaciotat.com/sejourner/les-infos-pratiques/parkings/).
Les deux secteurs ont été testés.

Dans le cadrage reproduit, `7` vient du layer `nowave-depth-soundings`, source
`nowave-soundings`, source-layer `sounding`. Feature
`emodnet-dtm-2024:27046:39948`, coordonnée MVT (5.6130213, 43.1734366) :
`value_original=-7.2879996 m`, `value_m=7.2879996 m`, datum LAT,
`depth_label=7`, `nature=modeled_grid_cell`, `interpolation_flag=0`,
`value_count=16`, `cdi_index=17776`. Ce n'est ni un chiffre Mapbox de fond ni
une sonde originale SHOM. Le flag 0 ne transforme pas un DTM en levé ponctuel.
[Attributs complets](../../test-results/marine-final-2026-10-18/final-ciotat-comparison-z15.8-rendered.json),
[capture du chiffre et des balises](../../test-results/marine-final-2026-10-18/final-ciotat-comparison-z15.8.png).

### Sources françaises recherchées et décision

| Candidat officiel | Données / couverture / disponibilité | Référence, résolution, licence | Décision |
|---|---|---|---|
| [Levés bathymétriques SHOM](https://diffusion.shom.fr/leves-bathy.html) | XYZ originaux téléchargeables ; quatre levés locaux déjà archivés, 7 795 échantillons, acquisition 2005–2013 | WGS84, mètres ; LAT explicitement dans les fichiers locaux ; précision individuelle non publiée ; Licence Ouverte 2.0, citation/DOI SHOM | Source réelle existante, conservée intégralement, mais exclue du flux numérique européen par le choix EMODnet du MVP |
| [MNT façade Golfe du Lion–Côte d'Azur HOMONIM](https://diffusion.shom.fr/donnees/bathymerie/mnt-facade-gdl-ca-homonim.html) | MNT régional, formats numériques ASC/GRD/BAG/GLZ annoncés | Pas 0,001° ≈111 m N–S, WGS84 ; variantes niveau moyen/PBMA ; produit ouvert, attribution SHOM 2015 | Pas une amélioration portuaire native ; aucune ingestion ni conversion de datum |
| [Litto3D PACA 2015](https://diffusion.shom.fr/donnees/litto3d-paca-2015.html) | Points XYZ et grilles ASC en dalles ; couverture littorale, pas de garantie de levés dans chaque bassin | RGF93/Lambert93, altitudes IGN1969 ; grilles fines selon produit, précision dépendant du capteur ; conditions et attribution à qualifier pour chaque livraison | Pas LAT. Ne pas convertir ces altitudes en profondeurs par simple changement de signe ; aucun nouveau jeu ingéré |
| Données portuaires locales | Recherche ciblée des publications officielles portuaires/CCI/TPM | Aucun flux XYZ de bassin actuel, librement exploitable et avec datum/licence complètement qualifiés trouvé pendant cette mission | Aucun ajout ; cela ne prouve pas l'inexistence générale de tels jeux |

Le [descriptif Litto3D](https://diffusion.shom.fr/media/wysiwyg/pdf/DC_Litto3D.pdf)
mentionne notamment des nœuds fictifs de grille dans des ports aplanis, identifiés
par un masque de provenance. Une grille à mailles fines ne suffit donc pas à
garantir des sondes portuaires originales. Les conditions du produit et la
provenance de chaque livraison doivent précéder toute intégration.

Le flux européen conserve les centres du DTM EMODnet 2024 à 1/960°, environ
116×85 m à Toulon, mètres/LAT, CC BY 4.0. Labels arrondis au mètre, `<1` sous
un mètre, valeur numérique originale conservée. Strides Z12/13/14/15/16 :
32/16/4/2/1 ; Z17 réutilise Z16. Pas d'interpolation locale ni de nouvelle
résolution créée par le zoom. Vauban : 5 chiffres à Z14.8, 10 à Z16, 3 à Z17
dans un champ plus petit. Ce résultat n'est pas une cartographie SHOM complète.
[Port Z16](../../test-results/marine-final-2026-10-18/final-port-z16.png),
[port Z17](../../test-results/marine-final-2026-10-18/final-port-z17.png).

### États-Unis

Les sondes originales NOAA ENC Direct to GIS sont rétablies depuis Z14 dans la
couverture NOAA hors EMODnet. Le normaliseur préserve valeurs décimales,
unités et datum publié ; un datum absent reste absent, sans supposer MLLW.
Exemple Miami : `noaa:harbour:76:14453977`, valeur source
15.200000000000001 m, label 15.2, datum absent dans les propriétés rendues.
NOAA est attribué dans le registre existant, licence enregistrée CC0 1.0.
Le [service officiel](https://nauticalcharts.noaa.gov/learn/encdirect/) décrit des
données GIS transformées, qui ne remplacent pas le produit de navigation ENC.

Miami Z12 : aucune sonde NOAA ; Z16 : 37 résultats, Z17 : 11 dans un champ plus
petit. Cape Florida Z14 : 32. La sélection déterministe existante protège les
petites profondeurs ; une baisse du nombre à Z17 n'est pas une baisse de détail
par unité de surface. [Miami Z16](../../test-results/marine-final-2026-10-18/final-miami-z16.png),
[Miami Z17](../../test-results/marine-final-2026-10-18/final-miami-z17.png),
[Cape Florida Z14](../../test-results/marine-final-2026-10-18/final-cape-florida-z14.png).

## F. Losanges

L'identification et la correction étaient déjà réalisées le 17 octobre :
les anciens losanges avec point étaient des **obstructions SHOM**
`EPAVES_BDD_WFS:obstrn`, rendues par `nowave-hazard-points`, source
`nowave-underwater-hazards`, source-layer `underwater_hazard`. La famille
n'a pas été déduite de l'ancienne forme du pictogramme.
[Preuve historique avant correction](../../test-results/hydrography-corrective-2026-10-17/before-toulon.png),
[diagnostic antérieur](hydrography-corrective.md).

Nouvelle interrogation réelle à Vauban, centre (5.925,43.1145), Z14.8 : 23
dangers ponctuels rendus. Exemples actuels, préfixe source
`EPAVES_BDD_WFS:obstrn:` :

| ID publié | Géométrie MVT | Brassiage | Attribut publié |
|---|---|---:|---|
| `FR 0000139822 00003` | Point(5.9207028,43.1195850) | 9,1 m | précision horizontale 0,7 m |
| `FR 0000141715 00001` | Point(5.9230256,43.1212570) | 10,2 m | « Pioche de 6 tonnes. », précision horizontale 0,7 m |
| `FR 0000168177 00003` | Point(5.9247369,43.1204386) | 10,4 m | précision horizontale 0,7 m |

Les trois gardent `hazard_type=obstruction`, catégorie et `water_level`
inconnus ; le datum spécifique reste absent du feature, sans déduire LAT du
seul mot brassiage. Attributs source, coordonnées originales et provenance sont
conservés ; les coordonnées rendues sont quantifiées par MVT. Licence du jeu
SHOM : CC BY-SA 4.0, attribution dans le registre et sur la carte.

Rendu conservé : obstruction = enceinte ouverte interrompue avec trait central ;
épave = coque/mât ; roche = croix avec état publié ; inconnu = symbole neutre
distinct. Aucun véritable danger n'a été retiré pour améliorer l'esthétique.
[Vauban actuel](../../test-results/marine-final-2026-10-18/final-vauban-z14.8.png),
[features complètes](../../test-results/marine-final-2026-10-18/final-vauban-z14.8-rendered.json).
À Miami et Cape Florida, les statuts NOAA immergé/découvrant restent distincts.

## G. Points rouges et verts

**Défaut confirmé et corrigé dans cette mission :** les balises fixes latérales
à bandes horizontales vert/blanc ou rouge/blanc étaient rejetées par la logique
d'image héritée des bouées. Elles retombaient sur le point neutre, tandis que le
feu associé pouvait apparaître comme un petit signe coloré.

La vérification croise les MVT rendus et deux requêtes WFS SHOM ciblées
`BALISAGE_BDD_WFS:bcnlat` / `lights`, BBOX
5.610,43.170,5.617,43.176 EPSG:4326, limite 100 objets. Les données SHOM Balisage
sont sous Licence Ouverte 2.0 ; aucune extraction de carte protégée.
[Réponses originales conservées](../../test-results/marine-final-2026-10-18/ciotat-shom-original.json).

| Objet réel | Attributs SHOM vérifiés | Normalisation / rendu |
|---|---|---|
| Môle Bérouard, `FR000002363400001` | BCNLAT, catlam=2, colour=4,1, colpat=1, bcnshp=3, feu lié `FR000005228900001` | fixe latéral tribord IALA A, vert/blanc horizontal, support tour ; feu vert publié conservé |
| La Tasse, `FR000002343200001` | catlam=2, colour=4,1, colpat=1, bcnshp=5, feu lié `FR000005229400001` | fixe latéral tribord IALA A, vert/blanc horizontal ; feu vert conservé |
| Jetée de la Ciotat, `FR000002299900001` | catlam=1, colour=3,1, colpat=1, bcnshp=3, feu lié `FR000005227900001` | fixe latéral bâbord IALA A, rouge/blanc horizontal ; feu rouge conservé |
| Miami Fishermans Channel Light 9 / 7 | NOAA `harbour:1:179127` / `179125`, BCNLAT, bâbord, vert, système IALA B, feu vert | balises fixes vertes bâbord en IALA B, sans appliquer la règle française |

Quatre variantes originales sont ajoutées au générateur et aux assets existants :
`beacon-green-white`, `beacon-white-green`, `beacon-red-white`, `beacon-white-red`.
La sélection exige `type=beacon_lateral`, un motif horizontal, une catégorie et
un système IALA cohérents avec la couleur. Une couleur de feu seule ne suffit
jamais ; données manquantes ou contradictoires restent neutres. Les huit
combinaisons couleur/ordre/système ainsi que les cas insuffisants sont testés.

Ces supports étroits avec pied sont distincts des bouées flottantes ; ancrage
au pied et échelle portuaire existants conservés. Ils restent des symboles
abstraits NoWave, pas des reproductions photographiques des formes BCNSHP ni
des symboles certifiés INT1. Aucune marque de sommet absente n'est inventée.
La priorité existante du support qualifié évite la superposition de son feu ;
les informations du feu lié restent dans le feature. Un feu OpenWaters distinct
proche du Môle Bérouard n'est pas fusionné arbitrairement par proximité.

[Avant au même centre](../../test-results/marine-final-2026-10-18/before-ciotat-z15.8.png),
[après au même centre](../../test-results/marine-final-2026-10-18/final-ciotat-comparison-z15.8.png),
[balises rouges et vertes dans le même cadre](../../test-results/marine-final-2026-10-18/final-ciotat-laterals-z15.8.png),
[attributs IALA B à Miami](../../test-results/marine-final-2026-10-18/final-miami-z16-rendered.json).

## H. Architecture

La chaîne reste `provider → normalisation NoWave → MVT → Flutter/Mapbox`.
`DepthContour`, `Sounding` et `UnderwaterHazard` restent distincts. Aucun client
Flutter ne contacte directement SHOM ou NOAA.

| Endpoint backend | Source Mapbox / source-layer | Principaux layers |
|---|---|---|
| `/api/v1/map/bathymetry/{z}/{x}/{y}.png` | `nowave-bathymetry`, raster | `nowave-bathymetry-raster` |
| `/api/v1/map/depth-contours/{z}/{x}/{y}.pbf` | `nowave-depth-contours` / `depth_contour` | `nowave-depth-major`, `minor`, `labels` |
| `/api/v1/map/soundings/{z}/{x}/{y}.pbf` | `nowave-soundings` / `sounding` | `nowave-depth-soundings` |
| `/api/v1/map/underwater-hazards/{z}/{x}/{y}.pbf` | `nowave-underwater-hazards` / `underwater_hazard` | `nowave-hazard-points`, `areas`, `outlines` |

Le backend sélectionne EMODnet géographiquement, sinon `noaa-soundings` dans sa
couverture. Il ne bascule pas sur NOAA lors d'une panne EMODnet et ne réactive
pas SHOM. Le fournisseur NOAA de sondes réutilise le normaliseur/ENC existant,
minzoom 14, avec une instance de `MarineHTTP(persistent_cache=False)` : ni
ouverture SQLite ni second cache brut. Ce mode refuse explicitement les tuiles
OSM qui exigent leur cache historique. Les autres clients/caches sont inchangés.

Les chiffres gardent le cache MVT RAM existant : 512 tuiles/32 Mio/300 s.
Réponses HTTP `no-store`, source native `volatile=true`, maxzoom 16, version de
tuile `depths-4`. Flutter accepte les natures `modeled_grid_cell` et
`point_sounding` sans sélectionner le fournisseur. Les autres familles restent
sur leurs sources et règles de cache précédentes. Aucun cache n'a été effacé.

15 fichiers présents au départ ont été modifiés pendant cette mission :

```text
backend/app/application/services/marine_tiles.py
backend/app/domain/hydrography.py
backend/app/infrastructure/marine/http.py
backend/app/infrastructure/marine/hydro_providers.py
backend/app/infrastructure/marine/runtime.py
backend/app/infrastructure/marine/sources.py
backend/tests/unit/test_emodnet_depths.py
docs/architecture/emodnet-depths.md
mobile/assets/icons/fixed-aids/README.md
mobile/lib/core/map/marine/marine_map_controller.dart
mobile/lib/features/map/data/fixed_aid_layer.dart
mobile/lib/features/map/data/hydrography_layer.dart
mobile/test/features/map/data/fixed_aid_layer_test.dart
mobile/test/features/map/data/hydrography_layer_test.dart
mobile/tool/make_fixed_aid_icons.py
```

Le contrôleur raster reçoit une URL injectable pour tester son installation ;
son défaut reste le dart-define. Les nouveaux fichiers de cette mission sont
deux fichiers de tests, quatre PNG et ce rapport ; liste exhaustive en N.

## I. Android

LGN LX1 physique, `AV5PJV6328H03108`, Android 15/API35, arm64, USB. Confirmé par
`flutter devices`. Reverse existant `tcp:8004 → tcp:8004` conservé.
`/health` et `/openapi.json` : HTTP 200 avant et après le rechargement local du
backend nécessaire à NOAA. Aucun déploiement distant.

Commande réellement exécutée depuis `mobile/` :

```bash
/home/palms/flutter/bin/flutter build apk --debug --no-pub \
  --dart-define-from-file=.env.json \
  --dart-define=MARINE_API_BASE_URL=http://127.0.0.1:8004/ \
  '--dart-define=BATHYMETRY_TILES_URL=http://127.0.0.1:8004/api/v1/map/bathymetry/{z}/{x}/{y}.png'
adb -s AV5PJV6328H03108 install -r build/app/outputs/flutter-apk/app-debug.apk
```

Build final réussi en 9,5 s, installation `Success`, package `fr.blueway.app`,
version 1.0.0, dernière mise à jour Android 18/10/2026 14:44:26 heure locale.
APK : 259 533 534 octets, SHA256
`1915278dc9da50023419b67e6805bef0dd1e975b7a6a7ab37eea4c64824a7ca4`.
[Build](../../test-results/marine-final-2026-10-18/apk-build-final.log),
[installation](../../test-results/marine-final-2026-10-18/install-final.log).
Le SHA256 de `base.apk` lu directement sur le téléphone est identique au build
local : [comparaison APK installée](../../test-results/marine-final-2026-10-18/installed-apk.json).
Avertissement Gradle existant sur les plugins Kotlin, sans échec du build.
Installation avec conservation des données, sans désinstallation ni `pm clear`.

Une instrumentation ASGI locale temporaire, extérieure au dépôt, enregistre
uniquement les requêtes de tuiles, statuts, durée et User-Agent ; pas les corps
ni les en-têtes d'authentification. Les vraies requêtes PNG/MVT portent :
`fr.blueway.app/1.0.0/1 MapboxCoreMaps/11.30.1 MapboxCommon/24.30.1 Android (15; HNLGN-QL (arm64-v8a; LGN-LX1))`.
[Journal des requêtes](../../test-results/marine-final-2026-10-18/device-requests.jsonl),
[synthèse](../../test-results/marine-final-2026-10-18/request-summary.json).

Les 17 cadrages finaux ont leurs coordonnées, zooms natifs et comptages dans
[final-scenes.jsonl](../../test-results/marine-final-2026-10-18/final-scenes.jsonl).
Le [manifeste des images examinées](../../test-results/marine-final-2026-10-18/reviewed-images.json)
conserve leurs empreintes, dimensions et contextes de capture.
Outre les vues déjà liées :

| Secteur | Centre longitude, latitude | Zoom | Capture examinée |
|---|---|---:|---|
| Marseille / Frioul | 5.308,43.278 | 13.7 | [Image](../../test-results/marine-final-2026-10-18/final-marseille-z13.7.png) |
| Giens | 6.12,43.04 | 14 | [Image](../../test-results/marine-final-2026-10-18/final-giens-z14.png) |
| Miami | −80.145,25.758 | 12 | [Image](../../test-results/marine-final-2026-10-18/final-miami-z12.png) |
| Miami | −80.157,25.763 | 16 / 17 | Images liées en E |
| Cape Florida | −80.155,25.67 | 14 | Image liée en E |

Les coordonnées affichées en haut à gauche sont celles du GPS, pas celles du
centre de caméra : elles restent françaises pendant les déplacements de caméra
aux États-Unis, sans usurper une position GPS américaine. Les centres testés
sont attestés par la caméra native et le journal des cadrages.

GPS réel : tap ADB sur le bouton, arrivée à Z15.500000000000002, centre
(5.9340317,43.0851730), `_isFollowing=false`. Glissement tactile : centre
(5.9353191,43.0851730), stable deux secondes plus tard, suivi toujours désactivé.
[Mesures GPS](../../test-results/marine-final-2026-10-18/gps-proof.json),
[arrivée Z15.5](../../test-results/marine-final-2026-10-18/final-gps-arrival-z15.5.png),
[déplacement libre](../../test-results/marine-final-2026-10-18/final-gps-pan-free.png).
Symbole bleu, bord clair et halo existants conservés, sans recoloration.

La [vue de non-régression Z12](../../test-results/marine-final-2026-10-18/final-other-aids-reports-z12.png)
montre bouées, repère cardinal, phare, points neutres sombres, signalement
orange, position GPS et badge Z. L'inventaire natif constate notamment 28
bouées rendues, 2 phares et 1 balise principale dans les 50 premiers résultats.
La [fiche d'un signalement existant](../../test-results/marine-final-2026-10-18/final-existing-report.png)
et le [formulaire de création](../../test-results/marine-final-2026-10-18/final-report-form.png)
ont été ouverts réellement, puis fermés sans publier de nouveau signalement.
Les signalements conservent leur API distante existante ; les endpoints marins
testés utilisent le backend local. Aucun contenu utilisateur n'a été ajouté.

## J. Tests

Commandes exécutées sur le code final, sauf documentation ajoutée ensuite :

| Commande | Résultat |
|---|---|
| `PYTHONMALLOC=malloc /tmp/nowave-hydro-corrective/venv312/bin/python -m pytest -q` depuis la racine | **825 réussis, 0 échec, 0 ignoré**, 4,55 s |
| `.venv/bin/ruff check backend` | Tous les contrôles passent |
| `/home/palms/flutter/bin/dart format --output=none --set-exit-if-changed lib test` depuis mobile | 167 fichiers, 0 modification |
| `/home/palms/flutter/bin/flutter analyze --no-pub` depuis mobile | Aucune anomalie, 2,5 s |
| `/home/palms/flutter/bin/flutter test --no-pub` depuis mobile | **490 réussis, 0 échec, 0 ignoré** |
| `git diff --check` | Code retour 0 |

[Pytest](../../test-results/marine-final-2026-10-18/pytest-final.log),
[Ruff](../../test-results/marine-final-2026-10-18/ruff.log),
[formatage](../../test-results/marine-final-2026-10-18/dart-format.log),
[analyse Flutter](../../test-results/marine-final-2026-10-18/flutter-analyze.log),
[tests Flutter](../../test-results/marine-final-2026-10-18/flutter-tests.log).
Un avertissement préexistant Starlette/TestClient/httpx subsiste. L'interpréteur
Python 3.12 de validation déjà disponible a été utilisé car l'environnement
3.14 avait montré des segfaults Pillow dans les travaux précédents ; aucune
dépendance de production n'a été changée.

Ajouts : six cas backend sur restauration géographique NOAA, seuil Z14,
conservation profondeur/datum inconnu, absence de repli après panne EMODnet,
absence de SQLite/fichiers avec HTTP numérique, protection du cache OSM ;
quatre tests Flutter raster (installation unique/reload, opacité/overzoom,
erreur retentable, ordre texture/contours) ; un test de combinaisons IALA pour
les nouvelles balises. Les tests existants de synchronisation des labels,
classification des dangers, bouées, GPS, session et signalements sont conservés.

## K. Revue 1

Première passe : lecture du diff local, comparaison aux rapports hydrographiques
précédents et inspection avant correction sur appareil. Conclusions corrigées :

1. Panne du raster due à l'URL de l'APK : correction de configuration, sans
   modification arbitraire de la palette ou de l'ordre des couches.
2. Balises latérales à bandes blanches auparavant neutres : ajout de quatre
   variantes fixes et sélection stricte d'après classe, motif et IALA.
3. Chiffres NOAA écartés par le MVP précédent : restauration géographique
   expressément choisie par l'utilisateur, client numérique sans cache disque.
4. Répétition constante : expression par zoom, puis correction de l'essai
   128/144 px après perte réelle des inscriptions 50. Valeur finale 160 px aux
   zooms 12–14, vérifiée après recompilation.
5. Rapport précédent trop ancien pour décrire l'état réel : les losanges étaient
   déjà corrigés, les sondes françaises choisies étaient désormais modélisées.

Les tests concernés, puis les deux suites complètes, ont été exécutés après
les corrections. Les tentatives intermédiaires restent dans les journaux :
aucune capture d'essai n'est présentée comme le réglage final.

## L. Revue 2

Seconde passe à partir des exigences et des preuves de l'APK finale, séparée
de la lecture du diff : ouverture des captures, vérification des attributs
Mapbox natifs et des réponses réelles du backend.

| Exigence | Constat séparé |
|---|---|
| Bleu réel / pas de couleur fictive | PNG multicolores et captures françaises concordants ; Miami PNG transparent, critère raster USA non atteint |
| Z11.9 / Z12 | 0/0 puis 5 labels/5 fragments visibles au même centre ; attributs 50/100/200/500 |
| Taille / répétition | Expressions natives correspondent au tableau C ; répétition 50 visible sans forcer les collisions |
| Lignes sans profondeur | Aucun ID de ligne effectivement visible sans label placé dans les 17 cadrages contrôlés |
| Précision française | Contours généralisés absents Z15.8/Z17, fond raster et chiffres modélisés conservés |
| Sondes et chiffre 7 | Cellule exacte EMODnet identifiée ; NOAA original distinct, datum absent conservé |
| Dangers / losanges | 23 dangers Vauban, familles/statuts source conservés ; symboles distincts examinés |
| Repères latéraux | WFS original + MVT ; vert/blanc tribord A, rouge/blanc bâbord A ; vert bâbord B réel à Miami |
| Feux simples | Aucune règle de conversion d'un feu seul en balise ; données liées conservées, exemple de phare et de feu sur ouvrage dans les captures |
| Reload / URL / doublons | Rechargement natif et double installation réussis ; URL locale, IDs uniques, source de chiffres volatile |
| Bouées / ports / GPS / interface | Bouées, quais, phares, cardinal, points neutres, badge, coordonnées et symbole GPS réellement visibles ; GPS one-shot et pan tactile mesurés |
| Signalements | Affichage, fiche existante et ouverture du formulaire validés sur téléphone ; publication réelle non exécutée |
| Réseau / performances | Requêtes LGN attestées ; 503 NOAA et annulations présents, pas de promesse de disponibilité continue ni mesure FPS contrôlée |

L'inspection a aussi détecté un piège du protocole de validation :
`queryRenderedFeatures` renvoie certaines géométries dont la peinture est
transparente. Le premier contrôle brut Miami comptait à tort 238 fragments
comme visibles. Le contrôle final utilise l'état `label_visible` réel, soit
19 fragments visibles à Miami Z12. Le JSON brut est conservé ; ce n'était pas
une régression de l'application. Une erreur temporaire de helper (`literal`
au lieu de `string`) a été corrigée avant la collecte finale du style natif.

Les passages sont distincts et fondés sur deux méthodes de vérification,
mais effectués par **le même agent** : ils ne constituent pas deux avis de
personnes ou d'agents indépendants. Les résultats ne permettent pas d'annoncer
une validation exhaustive de chaque catégorie nautique dans chaque secteur.

## M. Limitations

- **Raster USA absent dans la zone contrôlée.** Miami 12/1135/1744 renvoie un
  PNG de 334 octets entièrement transparent, alpha 0…0. Le bleu uniforme
  Mapbox visible ne représente aucune profondeur. Le même fond uniforme est
  observé à Cape Florida ; aucune couverture raster locale supplémentaire
  n'a été ajoutée. [PNG réel Miami](../../test-results/marine-final-2026-10-18/backend-miami-z12.png).
- **Pas de nouvelle précision portuaire française.** La politique européenne
  EMODnet conserve un modèle d'environ 116 m, avec cellules manquantes et
  décalages possibles du littoral. Les levés SHOM historiques sont bien
  disponibles dans l'archive locale, mais leur réactivation n'est pas autorisée
  par le choix retenu pour ce MVP. Aucun faux chiffre ni faux chenal ajouté.
- **Incidents réseau NOAA.** Sur la fenêtre de journalisation complète des
  essais, 49 réponses 503 : 32 sondes, 9 contours, 8 dangers, toutes dans les
  requêtes américaines, entre 12:56:22 et 13:01:18 UTC. Les requêtes ultérieures
  ont permis les captures finales détaillées. 16 demandes de sondes annulées
  portent 499. Le journal ne permet pas d'attribuer chaque 503 à une cause
  amont précise ; aucune disponibilité continue n'est revendiquée.
- Les durées réseau comprennent des caches chauds/froids, déplacements et
  fournisseurs différents : ce ne sont pas un benchmark. Aucun FPS, autonomie
  ou temps de rendu garanti n'est déduit de cette session debug.
- La configuration native volatile et l'absence de persistance numérique
  Python sont vérifiées ; tous les effets internes de cache Android/Mapbox
  n'ont pas été audités.
- Le formulaire de signalement a été ouvert sans publication. Les tests
  automatisés de création passent ; un nouveau signalement réel n'a pas été
  envoyé à l'API distante. Toutes les catégories de bouées ne sont pas présentes
  dans les vues choisies ; leur matrice reste couverte par les tests existants.
- Aucune revendication de sondes officielles françaises supplémentaires, de
  carte SHOM complète ou de produit de navigation certifié. Datums et qualités
  inconnus restent inconnus.

## N. État Git final

La branche et le HEAD sont inchangés, l'index également. 705 fichiers hors
ignorés : **683 des 698 fichiers initiaux sont identiques**, 15 ont une
modification intentionnelle et 7 sont nouveaux. Aucun fichier initial supprimé.
Les 10 chemins contenant `shom` et tous les anciens PNG d'icônes sont identiques
octet par octet à la sauvegarde. Tous les changements préexistants restent
présents. L'unique modification de configuration ignorée est la clé raster
décrite en B ; les preuves ignorées sont ajoutées et conservées.

`git diff --stat` par rapport au HEAD : 21 fichiers suivis modifiés,
512 insertions, 58 suppressions. Les fichiers déjà non suivis au départ ne
figurent pas dans ce total ; le statut détaillé ci-dessous les inclut.
7 fichiers créés pendant cette mission :

```text
backend/tests/unit/test_noaa_soundings.py
docs/test-reports/marine-final-2026-10-18.md
mobile/assets/icons/fixed-aids/beacon-green-white.png
mobile/assets/icons/fixed-aids/beacon-red-white.png
mobile/assets/icons/fixed-aids/beacon-white-green.png
mobile/assets/icons/fixed-aids/beacon-white-red.png
mobile/test/core/map/marine/marine_map_controller_test.dart
```

Les sorties finales de `git status --short --untracked-files=all`,
`git diff --stat`, `git diff --check` et l'audit SHA256 sont conservées dans
[git-final.txt](../../test-results/marine-final-2026-10-18/git-final.txt) et
[integrity-final.json](../../test-results/marine-final-2026-10-18/integrity-final.json).
Le statut compte 21 fichiers suivis modifiés et 35 fichiers non suivis.
Les instantanés et le diff propre à la mission restent également dans la
sauvegarde extérieure indiquée en A. `git diff --check` : aucune anomalie.

**AUCUN COMMIT — AUCUN PUSH — AUCUNE PR.**
