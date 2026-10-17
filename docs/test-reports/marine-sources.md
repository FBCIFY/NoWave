# Validation des sources marines NoWave

Recherches, probes réseau et captures : 16 octobre 2026. Seconde revue et finalisation :
17 octobre 2026. Validation locale ; aucun déploiement distant. Les données sont
transformées pour l'affichage et ne constituent pas une carte de navigation.

## A. Git initial

Branche `feature/marine-bathymetry`, HEAD `4fff447f` —
`feat(map): add bathymetry and port infrastructure layers`.
L'état initial correspondait à la demande : MapScreen et pubspec modifiés ;
BuoyLayer, ses PNG, tests, générateur et rapport bouées non suivis.
Ces fichiers ont été conservés. Les anciennes captures bouées ne sont pas présentées
comme des captures de cette mission.
[Relevé initial](evidence/marine-sources/git-initial.txt).
La ligne du nouveau répertoire `marine-sources/` y provient du relevé lui-même.

## B. Architecture

`Tile(z,x,y)` + famille → sélection par couverture réelle → providers indépendants
→ modèles WGS84 spécialisés → fusion conservative par objet → MVT NoWave → styles
Flutter existants. Aucun paramètre GPS ou identité utilisateur ne choisit un provider.
Le téléphone, resté à Toulon, a affiché les objets NOAA en déplaçant uniquement la caméra
à Miami. Les tuiles qui croisent plusieurs couvertures peuvent sélectionner plusieurs
autorités. Les fallbacks restent toujours admissibles.

[Architecture, flux, catalogue, licences, mappings et exploitation](../architecture/marine-sources.md).
Les nouveaux composants sont dans `backend/app/domain/marine*.py`,
`application/ports/marine_provider.py`, `application/services/marine_*.py` et
`infrastructure/marine/`. Les clients externes sont injectables ; les tests standards
n'utilisent pas Internet. Les contrôleurs reports, GPS et bathymétrie sont conservés.

## C. Providers et jeux

La matrice détaillée liée ci-dessus vérifie séparément couverture, formats, mise à jour,
licence, attribution, cache, transformation, redistribution et limites de chaque famille.
Les liens pointent vers les autorités et métadonnées officielles.

| Provider / pays | Dataset / famille | Accès | Licence / redistribution | Implémenté / raison |
|---|---|---|---|---|
| SHOM / France | Balisage maritime / aides | WFS ouvert, objets et topmarks | LO 2.0, tuiles dérivées avec crédit | Oui, cinq bouées |
| SHOM / France | Informations portuaires / ports | WFS | LO 2.0 | Non : postes/zones/docks flottants ne sont pas des quais ou digues génériques |
| IGN / France | BD TOPO, construction_lineaire nature=Quai / ports | WFS 2.0 GeoJSON CRS84 | LO 2.0, source et édition | Oui, ouvrages en service, sous-types vérifiés |
| NOAA / USA | ENC Direct / aides | ArcGIS query GeoJSON | ENC CC0 ; crédit conservé | Oui, cinq bouées et topmarks |
| NOAA / USA | ENC Direct SLCONS/DOCARE / ports | Six échelles, classes réelles | Même jeu CC0 | Oui, lignes/surfaces, fusion inter-échelles |
| CHS / Canada | Maritime Chart Service / aides | WMS/SOE d'affichage ; query testé invalide | Service OGL Canada ; ENC vendus distincts | Non, extraction vectorielle exhaustive non validée |
| CHS / Canada | Même service / ports | Même blocage distinctement vérifié | Pas d'ouverture déduite des fichiers ENC | Non, OSM conservé |
| AMSA / Australie | Aids to Navigation 2025 / aides | Archive vectorielle annoncée | Spatial@AMSA CC BY-NC 3.0 AU | Non, autorisation commerciale NoWave non établie |
| AMSA / Australie | Réseau AtoN / ports | Pas de dataset de quais établi | Licence AtoN non transposable | Non |
| AHO / Australie | AusENC / aides | Produit sous licence | Dérivés soumis à accord | Non, accord absent |
| AHO / Australie | AusENC / ports | Même produit | Même restriction | Non |
| LINZ / NZ | Hydrographic LDS / aides | WFS avec clé personnelle | À vérifier couche par couche | Non, aucune clé disponible, confirmé par l'utilisateur |
| LINZ / NZ | Shoreline construction polygon 50611 / ports | LDS, 36 objets 1:22k–1:90k | Cette couche : CC BY 4.0 | Non, clé absente ; pas de généralisation de licence |
| Open Waters / monde | Seamap / aides | XYZ MVT | CC BY 4.0 + OSM/ODbL | Oui, fallback permanent |
| OSM / monde | Shortbread / ports | XYZ MVT | ODbL + politique serveur ≥7 jours de cache | Oui, fallback permanent |

Aucun faux adapter CHS, AMSA, AHO ou LINZ. Vancouver sélectionne aussi le masque
ENC NOAA qui déborde la frontière ; les requêtes réussies n'y ont renvoyé aucun objet.
Cela ne valide aucun jeu CHS. Sydney et Auckland valident les fallbacks uniquement.

## D. Endpoints et contrat

- `/api/v1/map/seamarks/{z}/{x}/{y}.pbf` : `seamark`.
- `/api/v1/map/port-infrastructure/{z}/{x}/{y}.pbf` : `port_infrastructure` canonique,
  plus `water_polygons`, `pier_lines`, `pier_polygons` pour les styles existants.
- `/api/v1/map/marine-sources` : crédits, jeux, familles et liens de licence publics.

Deux endpoints isolent les familles et conservent les contrats source-layer existants.
MVT extent 4096, projection Web Mercator, buffer 64, z0–14 puis overzoom natif.
Sous z10 : tuile vide valide sans requête amont. XYZ invalide : 422. Tout indisponible :
503. Statut `ok` ou `degraded`, sources effectives et lien des crédits dans les headers.
`ok` signifie réussite des appels sélectionnés, jamais exhaustivité d'un pays.

Propriétés communes : ID stable, source/source_id/source_priority, source_updated_at,
source_date, name, scale/scamin, provenance, external_ids. Bouées : type/category/color/
color_pattern/shape/topmark_shape/topmark_color/navigation_system/inferred_fields.
Ports : infrastructure_type/harbour/source_category. Les tuples deviennent du JSON texte.
Les vues de présentation ne gonflent pas le nombre d'objets du modèle canonique.

## E. Normalisation

Modèles `SeamarkFeature` Point et `PortInfrastructureFeature` Point/LineString/
MultiLineString/Polygon/MultiPolygon. Géométries valides WGS84 lon/lat ; IGN 3D ramené
explicitement en 2D. Aucun échange latitude/longitude ni altitude assimilée à une sonde.

S-57 édition 3.1 : couleurs, motifs, CATLAM/CATCAM, BOYSHP et TOPSHP normalisés ;
valeurs inconnues conservées. IALA A/B préservé : NOAA B ; SHOM A, sauf territoires
américains B documentés. L'absence de système Open Waters reste une absence ; Flutter
utilise alors la couleur publiée sans inventer un côté régional. SORDAT reste une date
de source et ne devient pas une fausse révision. Les topmarks SHOM se joignent par
identité ; NOAA par cellule, échelle et colocalisation exacte.

IGN Ponton → pontoon, Brise-lames → breakwater, Epi → groyne. Le ponton utilise la fine
ligne de ponton existante. Les quais linéaires, jetées génériques et constructions
ambiguës restent canoniques sans style arbitraire. NOAA distingue SLCONS terrestre
de DOCARE aquatique. Aucun port complet ni bassin administratif n'est inventé.

## F. Déduplication

Points : type identique, distance bornée, attributs non contradictoires, identité/nom ou
plusieurs attributs réellement publiés. La distance seule et la forme inférée Open Waters
ne suffisent jamais. Une correspondance concurrente avec deux objets officiels reste ambiguë.
Les objets différents d'un même jeu ne fusionnent pas automatiquement.

Lignes : compatibilité sémantique, longueur/orientation/Hausdorff, intersection ou ancres
ou nom commun. Deux quais parallèles à 1 m restent distincts sans preuve supplémentaire.
Polygones : IoU ≥0,82 ; ligne dans empreinte étroite : inclusion et longueur corroborées.
Géométries hétérogènes incertaines conservées. Le découpage MVT garde les composants
de la dimension source lorsqu’une tangence produit une GeometryCollection, sans créer
de nouveaux points ou provoquer une erreur d’encodage. NOAA privilégie l'échelle la plus détaillée
pour un match, sans supprimer toutes les échelles moins fines.

La priorité officielle s'applique à l'objet correspondant. Les provenances sont réunies.
Les cas ambigus restent visibles ; **une absence absolue de doublons n'est pas démontrée**.
Au Port du Manteau, deux paires proches restent à z17,5 : SHOM No1/No2 et Open Waters
12888316272/12888316271. Open Waters n'apporte ici qu'une couleur indépendante, sans
nom, catégorie, système ni topmark. La forme `pillar` est inférée. Les conserver respecte
la règle de non-destruction ; les supprimer par proximité contredirait les exigences.

## G. Fallbacks et panne/reprise

Open Waters reste présent pour les aides et Shortbread pour les ports, y compris dans
les zones SHOM/IGN/NOAA. Les objets non appariés ne sont jamais supprimés en bloc.

[Probe HTTP 503 et reprise](evidence/marine-sources/outage-recovery.json) : les transports
SHOM et IGN échouent réellement en HTTP 503 simulé ; les tuiles mondiales réelles restent
utilisées. Tuile 12/2115/1503, avec buffer : aides 80 → 17 → 80 ; infrastructures canoniques
303 → 114 → 303. Les octets et SHA-256 restaurés sont identiques à l'état initial.

Sur le téléphone, même application, mêmes styles et même caméra (5.913,43.095,z14) :
9 features de bouées interrogées → 6 en panne → 9 restaurées. Providers rendus :
SHOM/IGN/Open Waters/OSM → Open Waters/OSM → ensemble initial. Les deux pontons IGN
inspectés à z17 disparaissent puis reviennent. Chaque source/couche testée reste unique ;
GPS disponible, report layer installé, map_error null. Les requêtes NoWave continuent en 200
avec statut dégradé. Aucun endpoint de simulation ni application de démonstration ajouté au dépôt.
La simulation native utilise une seconde instance locale du vrai backend, avec injection
HTTP 503 limitée aux transports nationaux, puis restaure l'instance normale.

## H. Comparaison des bouées

Probes explicites d'une tuile z12 demandée par zone, pas un inventaire de ville entière.
Comptes sans buffer ; les comptes MVT/natifs peuvent différer. Officiel seul et OSM seul
signifient « non apparié dans les flux reçus ». Conflits = couples, pas nombre d'objets distincts.
Les 18 rapprochements entre échelles NOAA sont comptés avant la fusion avec le fallback.

| Zone / tuile z12 | Officiel brut → distinct | Fallback | Matchs | Officiel seul | OSM seul | Conflits | Résultat |
|---|---:|---:|---:|---:|---:|---:|---:|
| toulon / 2115/1503 | 63 → 63 | 17 | 3 | 60 | 14 | 6 | 77 |
| miami / 1136/1744 | 36 → 18 | 0 | 0 | 18 | 0 | 0 | 18 |
| vancouver / 647/1401 | 0 → 0 | 1 | 0 | 0 | 1 | 0 | 1 |
| sydney / 3768/2457 | 0 → 0 | 63 | 0 | 0 | 63 | 0 | 63 |
| auckland / 4036/2499 | 0 → 0 | 12 | 0 | 0 | 12 | 0 | 12 |

[Rapport brut et exemples attributaires](evidence/marine-sources/comparison-z12.json).
À Toulon, trois matchs sûrs : SHOM FR000058117500003 ↔ OSM 10080120763,
FR000058117700003 ↔ 10080120762, et safe-water FR000005243300001 ↔ 1420666201.
Positions et attributs normalisés sont comparés par les mêmes règles que le service.
La bouée cardinale SHOM LS1 (5.8933113,43.1061904), east, black_yellow_black, IALA A,
est réellement interrogée dans la couche native et visible à z17. À Miami, NOAA
harbour:6:140003 est port/green/IALA B et 140004 starboard/red/IALA B ; les deux
sont rencontrées dans l'application, sans doublon d'échelle ajouté. [Comparaisons attributaires et géométriques](evidence/marine-sources/aids-examples.json) :

| Objet / couple | Positions WGS84 | Attributs et décision |
|---|---|---|
| SHOM FR000058117500003 / OSM 10080120763 | (5.9010667,43.0833833) / (5.9010100,43.0833076), 9,60 m | Lateral port/red concordant ; match avec preuves supplémentaires ; officiel retenu |
| SHOM FR000005243300001 / OSM 1420666201 | (5.9588996,43.0834808) / (5.9588599,43.0834800), 3,23 m | Safe-water red_white vertical ; topmark sphere/red dans les deux sources ; provenances réunies |
| SHOM No1 / OSM 12888316272 | (5.9061833,43.09245) / (5.9060311,43.0925219), 14,73 m au z12 | SHOM starboard/green, topmark cone_up/green ; OSM seulement green, sans topmark ; ambiguïté conservée |
| NOAA harbour:6:140003 / approach:8:986404 | (-80.10901,25.7570789) dans les deux | Port/green/IALA B ; topmark non publié ; échelle harbour retenue, deux provenances et cellule ENC conservées |
| NOAA harbour:6:140004 / approach:8:986391 | (-80.1064556,25.7594289) dans les deux | Starboard/red/IALA B ; topmark non publié ; même fusion inter-échelles |

Les topmarks et
provenances sont conservés dans les fixtures et MVT, même si les icônes n'affichent pas
chaque attribut séparément. Open Waters à zéro dans cette tuile Miami z12 ne signifie
pas absence dans toute la ville ou à tous les zooms.

## I. Comparaison des infrastructures

| Zone / tuile z12 | Officiel brut → distinct | Fallback | Matchs | Officiel seul | OSM seul | Conflits | Résultat |
|---|---:|---:|---:|---:|---:|---:|---:|
| toulon / 2115/1503 | 191 → 191 | 114 | 4 | 187 | 110 | 48 | 301 |
| miami / 1136/1744 | 95 → 92 | 164 | 1 | 91 | 163 | 20 | 255 |
| vancouver / 647/1401 | 0 → 0 | 463 | 0 | 0 | 463 | 0 | 463 |
| sydney / 3768/2457 | 0 → 0 | 1193 | 0 | 0 | 1193 | 0 | 1193 |
| auckland / 4036/2499 | 0 → 0 | 433 | 0 | 0 | 433 | 0 | 433 |

| Zone | Types officiels distincts | Types OSM |
|---|---|---|
| toulon | pontoon: 71, quay: 111, jetty: 1, shoreline_construction: 3, breakwater: 4, groyne: 1 | dock: 10, pier: 96, breakwater: 7, groyne: 1 |
| miami | shoreline_construction: 49, pier: 33, quay: 4, breakwater: 4, groyne: 2 | pier: 137, groyne: 16, breakwater: 11 |
| vancouver | Aucun | dock: 4, pier: 453, groyne: 6 |
| sydney | Aucun | dock: 3, pier: 1184, groyne: 3, breakwater: 3 |
| auckland | Aucun | dock: 1, pier: 427, breakwater: 5 |

Les résultats canoniques comprennent les types actuellement non stylés ; 301 objets
canoniques à Toulon ne signifient pas 301 lignes de pontons visibles. Le MVT toulonnais
avec buffer contient notamment 10 docks, 162 lignes de présentation et 15 surfaces.
La source SHOM Balisage n'est jamais présentée comme source de quais.

## J. Objets officiels sans équivalent dans le fallback reçu

- IGN `CONSLINE0000002202525944`, ponton LineString centré vers
  (5.93248158,43.08353383), Saint-Mandrier : objet Shortbread le plus proche à 65,8 m
  dans le contrôle z14. Son voisin `CONSLINE0000002202525943` est aussi examiné dans
  le diagnostic des géométries. Les deux lignes apparaissent dans NoWave et disparaissent
  pendant la panne IGN. Autre ponton IGN `CONSLINE0000000074760575` : écart 67,2 m au relevé z12.
- NOAA `approach:89:8458551`, SLCONS `pier`, cellule US4FL2AI.000, LineString à trois
  sommets autour de (-80.14960788,25.79277747) : Shortbread le plus proche à 288,3 m
  au z14. La ligne native NoWave est interrogée et photographiée. SORDAT=20180609
  est une date de source, pas une preuve de fraîcheur terrain.

[Recontrôle z14](evidence/marine-sources/port-examples-z14.json) et
[diagnostic des géométries réelles](evidence/marine-sources/geometry-comparison.png),
image effectivement ouverte. Ce dernier est un tracé analytique, pas une capture Flutter.
« Sans équivalent » concerne les jeux interrogés, pas une preuve d'absence dans toute la base OSM.

## K. Objets seulement OSM dans les flux comparés

- Pier `pier_lines:14/8463/6013:fbdeac0391434f3ecab7`, quatre sommets autour de
  (5.96754584,43.10407349), près de Batterie Basse à l'est de la rade de Toulon :
  IGN renvoie zéro ouvrage dans cette tuile z14 ; la ligne OSM reste rendue.
  Cette localisation précise remplace l'appellation géographique approximative du suivi oral.
- À Miami : groynes autour de (-80.150864,25.738045) et (-80.15158,25.73778), à plus
  de 1 km des géométries officielles reçues au z12. Les piers OSM
  `14/4544/6976:83b112370563b84df929` et `:36e7860ccbe35c826916` restent aussi présents,
  à environ 473 et 471 m des objets NOAA interrogés.
- Vancouver 463, Sydney 1193 et Auckland 433 infrastructures du fallback conservées
  dans les tuiles sélectionnées ; aucun résultat national fictif ne les remplace.

Les IDs Shortbread sont des IDs de fragments de tuile, jamais annoncés comme des IDs OSM.

## L. Cardinales

[Diagnostic brut](evidence/marine-sources/cardinals.json). Dans la bbox
5.85,43.04,6,43.15, SHOM renvoie deux boycar : LS1 east et FR000065401300003 east.
Il renvoie séparément deux bcncar : FR000002344000001 north et Banc de l'Âne west.
Open Waters, tuile 12/2115/1503 : zéro buoy_cardinal mais trois beacon_cardinal
(1420666190 Banc de l'Âne west, 1420666195 north, 8489614456 north).
Ces balises fixes expliquent certaines cardinales attendues à tort parmi les bouées.
Elles sont diagnostiquées mais jamais ajoutées au filtre Flutter.

## M. Performance, cache et limites

8 accès HTTP simultanés, connexions/pool 2 s, timeout HTTP 4 s, collecte nationale 12 s,
budget provider externe 14 s incluant attente ; pas de boucle de retry par déplacement.
SHOM : six classes par parent z12 ; IGN : une requête filtrée ; NOAA : classes pertinentes
selon famille/emprise/échelle, au plus deux pages de 1000 par classe. Dépassement déclaré dégradé.
IGN ≤10 requêtes/s/processus ; au plus deux workers/IP sans limite globale adaptée.

Cache SQLite persistant 512 Mio, corps ≤8 Mio ; SHOM/NOAA 6 h, IGN/Open Waters 24 h,
OSM ≥7 jours ou max-age supérieur. Pas d'éviction fraîche OSM, bulk ni préchargement.
Cache final mémoire 512 entrées/32 Mio, 300 s ou 15 s dégradé ; single flight borné.
429/503 temporisés, Retry-After respecté ; erreurs non stockées comme données.

[Mesures locales](evidence/marine-sources/performance.json) : premier assemblage avec
cache HTTP déjà chaud, de 6 à 578 ms selon famille/zone, puis cache final <0,02 ms.
Zéro appel réseau dans cette mesure ; cela ne mesure pas le réseau à froid ni une charge
production. Sydney ports : 535490 octets, principale tuile mesurée. Les opérations Shapely/MVT
restent synchrones dans le processus : dimensionner les workers et mesurer avant forte charge.

## N. Tests et commandes

Python 3.12.15, dépendances de test installées depuis le fichier résolu ;
Flutter 3.47.6 / Dart 3.13.5. Les locks incluent mapbox-vector-tile 2.2.0 et Shapely 2.1.2 ;
protobuf est résolu en 6.33.6 pour respecter les contraintes réelles.

```sh
PYTHONPATH=backend /tmp/nowave-marine/py312/bin/python -m pytest backend/tests/api backend/tests/unit -q
.venv/bin/ruff check backend
cd mobile
/home/palms/flutter/bin/dart format --output=none --set-exit-if-changed lib/features/map/data/buoy_layer.dart lib/features/map/data/port_layer.dart lib/features/map/data/marine_tiles.dart lib/features/map/presentation/map_screen.dart test/features/map/data/buoy_layer_test.dart test/features/map/data/port_layer_test.dart
/home/palms/flutter/bin/flutter analyze
/home/palms/flutter/bin/flutter test
/home/palms/flutter/bin/flutter build apk --debug --dart-define-from-file=.env.json --dart-define=MARINE_API_BASE_URL=http://127.0.0.1:8001/ --dart-define=BATHYMETRY_TILES_URL=http://127.0.0.1:8000/api/v1/map/bathymetry/{z}/{x}/{y}.png
```

- Backend : **679 passed**, un avertissement préexistant Starlette/httpx ; lint réussi.
- Flutter : **468 passed**, analyze sans problème ; format vérifié.
- APK debug : construit avec le vrai `lib/main.dart` et la configuration réelle ;
  avertissement Kotlin de migration des plugins existants, sans échec.
- Fixtures minimales SHOM/NOAA/IGN/Open Waters/Shortbread autorisées, licences et URLs
  documentées dans `backend/tests/fixtures/marine/README.md`. Aucun test standard réseau.
- Tests : sélection des pays/frontière/outre-mer, modèles/IALA, topmarks, coordonnées,
  priorité, ambiguïtés, quais voisins, LineString/Polygon/MultiPolygon, panne/reprise,
  cache persistant, erreurs de payload non cachées, single flight, MVT et contrats Flutter/reload.
  Quatre couples de géométries IGN/Shortbread réelles sont aussi testés hors ligne, avec
  maintien de la géométrie officielle et réunion des provenances.

Probes live séparés : `backend/tools/compare_marine_sources.py` et
`backend/tools/probe_marine_outage.py`, avec PYTHONPATH=backend. Le catalogue se rafraîchit
explicitement avec `refresh_marine_catalog.py`. Aucun changement de CI pour obtenir du vert.
Les logs nettoyés des progressions de terminal sont dans le même répertoire de preuves.
[Headers HTTP réels](evidence/marine-sources/http-validation.json) : 200/ok avec les sources
officielles, 200/degraded avec les fallbacks en panne nationale.
[Appareil et hash de l’APK final](evidence/marine-sources/device-final.json).

## O. Validation visuelle sur appareil

`flutter devices` a identifié le LGN LX1, Android 15/API 35, ID actuel
AV5PJV6328H03108. Installation par `adb install -r`, application réelle
`fr.blueway.app`, session utilisateur conservée. Aucun main alternatif ni démo.
Backend NoWave local port 8001 via ADB reverse ; reports distants authentifiés conservés.
Pendant les captures comparatives, la bathymétrie est dirigée à l’exécution vers le
backend local existant port 8000. L’APK installé en fin de validation reçoit ce même
chemin via `BATHYMETRY_TILES_URL` à la compilation, sans modifier `.env.json` ni son code. La simulation native utilise le port 8002.

Chaque PNG ci-dessous a réellement été ouvert et inspecté :

| Capture | Caméra / observation |
|---|---|
| [Toulon port](evidence/marine-sources/toulon-port-z14.png) | 5.929,43.084 z14 ; ouvrages IGN/OSM, deux bouées jaunes, deux reports, flèche GPS |
| [Toulon intermédiaire](evidence/marine-sources/toulon-intermediate-z16.png) | 5.9061,43.09235 z16 ; latérales rouge/verte, collisions actives |
| [Toulon rapproché](evidence/marine-sources/toulon-close-z17_5.png) | Même centre z17,5 ; deux paires ambiguës conservées, limite explicitée en F |
| [Pontons officiels](evidence/marine-sources/toulon-official-pontoons-z17.png) | 5.9326,43.0835 z17 ; deux lignes IGN sans équivalent Shortbread reçu |
| [Pier OSM](evidence/marine-sources/toulon-osm-only-pier-z17.png) | 5.96755,43.10407 z17 ; ligne OSM conservée |
| [Cardinale LS1](evidence/marine-sources/toulon-cardinal-z17.png) | 5.8933113,43.1061904 z17 ; SHOM east, noir/jaune/noir |
| [Docks](evidence/marine-sources/toulon-docks-z16.png) | 5.9258,43.1186 z16 ; 7 features docks interrogées, surfaces discrètes |
| [Miami entrée du port](evidence/marine-sources/miami-port-z13.png) | -80.128,25.775 z13 ; dix features de bouées NOAA, ouvrages NOAA/OSM |
| [Miami intermédiaire](evidence/marine-sources/miami-intermediate-z16.png) | -80.10901,25.7570789 z16 ; bouée NOAA verte IALA B |
| [Miami rapproché](evidence/marine-sources/miami-close-z17_5.png) | Même centre z17,5 ; symbole vert unique, taille/interpolation conservées |
| [Miami ouvrage officiel](evidence/marine-sources/miami-official-only-pier-z17.png) | -80.14960788,25.79277747 z17 ; source_id NOAA 8458551 vérifié nativement |
| [Miami intérieur du port](evidence/marine-sources/miami-port-inner-z14.png) | -80.178,25.775 z14 ; piers et digues NOAA/OSM, aucun dock dans ce viewport |
| [Avant panne](evidence/marine-sources/toulon-national-before-z14.png) | 5.913,43.095 z14, 9 features de bouées interrogées |
| [Panne nationale](evidence/marine-sources/toulon-national-outage-z14.png) | Même caméra, 6 features, seulement Open Waters/OSM |
| [Pontons pendant panne](evidence/marine-sources/toulon-national-outage-pontoons-z17.png) | Les lignes IGN disparaissent ; surface OSM conservée |
| [Pontons restaurés](evidence/marine-sources/toulon-restored-pontoons-z17.png) | Même caméra, deux lignes IGN revenues |
| [Sources restaurées](evidence/marine-sources/toulon-national-restored-z14.png) | Même caméra z14 ; 9 features retrouvées, mêmes providers |
| [APK final installé](evidence/marine-sources/final-installed-app.png) | Configuration locale finale ; GPS, report, objets marins et bouton d’attribution hors zone système |
| [Style rechargé](evidence/marine-sources/toulon-reload-z14.png) | Retour caméra port ; sources/couches uniques, reports et GPS présents |

[Inspection native structurée](evidence/marine-sources/native-inspection.json) et
[propriétés natives](evidence/marine-sources/native-inspection.log). Ces comptages peuvent
inclure des fragments de tuile et des objets recouverts par l'UI : ne pas les assimiler à
un inventaire physique de symboles visibles.

Projection Mapbox `globe` conservée. BuoyLayer slot TOP, overlap=false,
ignorePlacement=false, padding=1, interpolation .30/.55/.85/1.0 aux z10/13/16/18 ;
ports slots BOTTOM/MIDDLE et valeurs graphiques existantes vérifiés dans le style natif.
Reports sans slot et overlap=true, donc au-dessus ; flèche GPS et danger orange restent
lisibles ensemble. GPS natif enabled=true, position présente, aucune erreur GPS/carte.
Après reload, un exemplaire de chaque source et couche testée. Bathymétrie : source unique,
URL locale attendue, HTTP 200 et teintes sous-marines présentes ; pas de nouvelle couverture
bathymétrique mondiale revendiquée (EMODnet reste son service préexistant).

Les crédits SHOM/IGN/NOAA/Open Waters/OSM, licences et avertissement de transformation sont
présents dans l'attribution de la source native directe XYZ. Un correctif final place les
ornements au-dessus de la zone système Android et initialise leur position dès la création
Mapbox. Le [menu final](evidence/marine-sources/native-attribution-final.png) a été ouvert par un tap
sur l’appareil et sa capture réellement inspectée : avertissement NoWave, IGN, SHOM/DOI,
Licence Ouverte 2.0, NOAA, Open Waters/CC BY 4.0 et OSM/ODbL sont lisibles.
Le texte libre était ignoré par Mapbox : la mention NoWave est désormais un lien vers
`marine-sources`, ce qui la rend visible dans le menu natif. L’APK final avec ce correctif
est installé ; aucune intervention supplémentaire de déverrouillage n’a été nécessaire.

## P. Première revue du diff

Relecture des nouveaux modèles, providers, schémas réels, routage, transport, fusion,
encodage, routes, dépendances, migration mobile, tests et documentation.
Corrections apportées :

- IGN rendu indépendant du masque des eaux SHOM, pour les ports intérieurs (Bordeaux testé).
- Correspondances multiples de points conservées ; quais parallèles à 1 m protégés.
- SORDAT distingué d'une date de révision, provenance des topmarks ajoutée.
- Payloads MVT invalides rejetés avant cache ; erreurs amont et limites explicitement dégradées.
- Padding de requête longitude/latitude en mètres corrigé, contrats Tile et erreur dans le domaine.
- IALA B et système inconnu traités sans supposer A ; Retry-After et plafond IGN ajoutés.

Tests complets et probes relancés après ces corrections. Les sorties restaurées du probe
retrouvent exactement les SHA initiaux. Les styles portuaires et assets locaux n'ont pas été refaits.

## Q. Seconde revue à partir des exigences

Deuxième passage de l'auteur depuis la demande complète, séparé de la première lecture ;
ce rapport ne prétend pas à une revue humaine externe. Recontrôle famille par famille des
jeux/licences et des exclusions ; architecture sans GPS ; fallback conservé ; géométries et
fusion ; contrats MVT/Flutter ; fixtures ; captures réellement ouvertes ; attributs natifs,
panne puis reprise et reload. Les catalogues et scripts explicites ont aussi été relus.

Constats/corrections de ce passage :

- La vue rapprochée française montre deux paires ambiguës : limite rendue explicite,
  aucune déclaration trompeuse « zéro doublon » ni fusion par couleur/distance seule.
- Une tangence lors du découpage peut produire une GeometryCollection non acceptée
  par l’encodeur : conservation des composants utiles de même dimension et test de
  régression sur quai polygonal et digue multiligne ; suite backend : 679 succès.
- Les nombres canoniques sont distingués des seules vues stylées et du buffer MVT.
- Les preuves « official-only » sont recontrôlées au z14 et limitées aux flux reçus ;
  l'absence dans tout OSM n'est pas affirmée.
- Le débogueur doit recevoir les mêmes dart-define que l'APK ; sinon son synchronisme
  peut rétablir l'URL par défaut. L'URL locale native a été vérifiée avant les captures retenues.
- L'attribution était trop basse dans la zone système Android : marge SafeArea et
  initialisation des ornements corrigées sans changer les symboles ni les styles marins.
  Le menu masque les textes HTML sans lien : avertissement NoWave rendu comme lien
  vers les métadonnées ; présence visible contrôlée sur l’appareil.
- Le fichier de dépendances avec hashes est régénéré pour Python 3.12 en conservant
  les contraintes du fichier de test. Les validations Flutter ont été relancées après
  le dernier ajustement d'attribution.

## R. Limites et mise en service

CHS non intégré faute d'extraction vectorielle exhaustive validée ; AMSA non intégré sous
la restriction NC constatée ; AHO sans accord de dérivés ; LINZ sans clé personnelle
(confirmé par l'utilisateur), licences à vérifier par couche avant extension. SHOM
Informations portuaires n'est pas un remplacement de quais. Les lignes IGN de quai/jetée
non assimilables à un style existant restent non stylées. Les providers ne sont jamais
déclarés exhaustifs ; échelles ENC, dates source, généralisation et omissions du fallback
limitent les comparaisons. Les ambiguïtés sont conservées et peuvent rester visibles.

Masques simplifiés/bufferisés et enveloppes IGN : indices de routage, pas frontières légales.
Débits et caches sont par processus ; cache persistant à monter et fournisseur Shortbread
à dimensionner avant charge significative. Aucun phares/feux/beacons/sondes/épaves/TSS
ajouté au rendu. Le téléphone et les probes n'établissent pas une qualification nautique.

Le backend distant n'a pas été déployé. **Déployer et vérifier ces routes avant de distribuer
un APK utilisant l'URL de production.** L'APK installé pour validation utilise le backend
local, accessible tant que la connexion ADB reverse et le service local restent disponibles.

## S. Git final

[État final](evidence/marine-sources/git-final.txt), diff stat suivi, inventaire des nouveaux
fichiers et vérification des espaces sont fournis. `git diff --check` ne couvre pas les non
suivis : un contrôle complémentaire les inclut. Les artefacts locaux bouées préexistants
sont conservés, sans nettoyage du working tree. Le contrôle complémentaire signale
uniquement l’absence préexistante de saut de ligne final dans `mobile/assets/icons/buoys/buoy.svg`,
laissé intact. Aucun défaut d’espacement dans les nouveaux textes de la mission.
Branche et HEAD inchangés.

**AUCUN COMMIT. AUCUN PUSH. AUCUNE PR.** Aucun reset, restore destructif, rebase ou amend.
