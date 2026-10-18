# NoWave — rapport local EMODnet DTM 2024

18 octobre 2026, Europe/Paris. Implémentation locale sur
`feature/marine-bathymetry`, HEAD `20437348` conservé. Aucun commit, push ou PR.
Aucune intervention GitHub, Linear, Drive, téléphone ou configuration ADB/USB.

## A. Architecture réellement implémentée

La source Flutter existante appelle `/api/v1/map/soundings/{z}/{x}/{y}.pbf`.
La route FastAPI utilise `MarineTileService`, qui sélectionne exclusivement
`EmodnetDepthProvider` pour les chiffres du MVP. Le fournisseur calcule une
sélection de centres EMODnet 2024 bornée à la tuile et interroge ERDDAP en CSV
avec stride. Les données sont vérifiées/normalisées en mémoire, puis encodées
par le générateur MVT existant, couche `sounding` et propriétés compatibles
`value_m`/`depth_label`.

Le SHOM n'est plus instancié comme fournisseur de chiffres dans le runtime ;
ses fichiers, outils et tests restent présents. NOAA reste utilisé pour les
autres familles mais est exclu de `SOUNDINGS` par le service. Aucun repli lors
d'une panne EMODnet. Aucune seconde architecture cartographique créée.

## B. Fichiers et justification

Les onze fichiers ci-dessous existaient dans l'état local initial et ont reçu
des modifications ciblées par rapport à la sauvegarde, incluant cinq fichiers
qui étaient déjà non suivis. Leur contenu antérieur est conservé hors dépôt.

| Chemin | Modification |
|---|---|
| `backend/app/api/routes/map_tiles.py` | Annulation après déconnexion, `no-store`, statuts des tuiles et 503 explicite pour les chiffres |
| `backend/app/application/services/marine_tiles.py` | Fournisseur unique, distinction hors couverture/vide/seuil, raisons réseau journalisées |
| `backend/app/domain/hydrography.py` | Ajout de `ModeledDepthCell` dérivé du contrat existant, avec indices et qualité |
| `backend/app/infrastructure/marine/hydro_encoding.py` | Z12, maintien de la sélection globale EMODnet, plafond/déduplication, labels arrondis et propriété des bordures |
| `backend/app/infrastructure/marine/runtime.py` | Instance EMODnet dédiée et fermeture du client ; autres fournisseurs conservés |
| `backend/app/infrastructure/marine/sources.py` | Attribution du DTM 2024, référence/licence/limites ; statut archivé SHOM et exclusion NOAA des chiffres MVP |
| `backend/tests/api/test_marine_tiles.py` | Contrat `no-store` et présence de la nouvelle attribution |
| `backend/tests/unit/test_hydrography.py` | Uniquement le seuil commun de non-requête des chiffres, de Z13 à Z11 ; tests SHOM inchangés |
| `mobile/lib/features/map/data/hydrography_layer.dart` | Source Z12–16, URL versionnée, `volatile`, filtre de cellules modélisées |
| `mobile/lib/features/map/data/marine_tiles.dart` | Attribution modélisation/LAT/DOI/licence/transformation, levés archivés distingués |
| `mobile/test/features/map/data/hydrography_layer_test.dart` | Assertions sur le nouveau contrat, attribution et politique de cache de la seule source de chiffres |

Cinq nouveaux fichiers :

| Chemin | Objet |
|---|---|
| `backend/app/infrastructure/marine/emodnet_depths.py` | Sélection ERDDAP, client sans persistance, décodeur strict et conversion |
| `backend/tests/unit/test_emodnet_depths.py` | 76 cas automatisés hors réseau, dont route réelle avec ERDDAP simulé |
| `backend/tools/probe_emodnet_depths.py` | Vérification réelle bornée à huit requêtes séquentielles, résumé JSON sans corps bruts |
| `docs/architecture/emodnet-depths.md` | Contrat, fonctionnement, limites et stockage |
| `docs/test-reports/emodnet-depths-2024.md` | Présent rapport |

Notamment **inchangés depuis l'état initial** : `shom_soundings.py`, l'ensemble
`data/shom-surveys`, `http.py`, `hydro_providers.py`, `hydro_normalization.py`,
les fixtures réelles, les outils SHOM, le contrôleur du fond marin et
`map_screen.dart`. Le travail préexistant sur ces fichiers n'a pas été réécrit.

## C. Fonctionnement ERDDAP et données

Les DDS/DAS ont été reçus en HTTP 200 avant implémentation. Dimensions croissantes
`[latitude=72000][longitude=75840]` ; pas nominal 1/960°, centres depuis
15.000520833333333°N et −35.99947916666667°E ; WGS84. `elevation` est en mètres
relativement au LAT et négatif sous le niveau de référence. La valeur manquante
est NaN ; les sentinelles de qualité sont −1/127/−1.

Le contrat détaillé et l'exemple de requête encodée sont dans
[l'architecture](../architecture/emodnet-depths.md). L'exemple initial de neuf
cellules à Toulon a reçu 608 octets CSV en HTTP 200 ; c'était une vérification de
syntaxe distincte de la campagne à huit régions ci-dessous. Il n'a pas été
conservé comme jeu de données.

Une seule requête par tuile demande `elevation,value_count,interpolation_flag,
cdi_index` avec les mêmes bornes d'indices et strides. Aucun téléchargement
d'emprise continentale. Aucun usage de `elevation_min/max` pour les chiffres.

Les cellules négatives finies donnent `value_m=-elevation`. Terre/valeur zéro,
NaN et indisponibilités ne deviennent pas des profondeurs nulles. Les qualités
disponibles restent attachées aux cellules ; absence de qualité et interpolation
ne constituent jamais des observations originales. Les identifiants correspondent
aux indices natifs, sans interpolation ni ajout au surzoom.

Licence vérifiée dans la [fiche officielle XML](https://sextant.ifremer.fr/geonetwork/srv/api/records/cf51df64-56f9-4a99-b1aa-36b8d7b743a1/formatters/xml) :
Creative Commons Attribution 4.0 International, restriction de navigation.
La [page EMODnet](https://emodnet.ec.europa.eu/en/bathymetry) donne le titre
EMODnet Digital Bathymetry (DTM 2024), le Consortium et le
[DOI cité dans NoWave](https://doi.org/10.12770/cf51df64-56f9-4a99-b1aa-36b8d7b743a1).
Le DAS contient aussi un avertissement générique de redistribution ; la licence
du produit a donc été contrôlée dans sa fiche plutôt que déduite de ce texte.

## D. Affichage cartographique

Z0–11 sans chiffres ni requête ERDDAP. Strides Z12/13/14/15/16 :
32/16/4/2/1. Sélection imbriquée par indices globaux, indépendante de l'ordre des
réponses et du déplacement ; aucune cellule dupliquée en bordure. Maximum dur
64 cellules/labels par tuile ; collisions natives activées. Au-delà de Z16,
Mapbox agrandit les mêmes cellules natives.

Label au mètre entier, demi-unités vers le haut, et « <1 » pour moins d'un mètre.
Exemple : 12.5 m → « 13 » ; la valeur numérique originale est conservée dans MVT.
Cette politique évite des décimales injustifiées pour le DTM.

Texte, halo, tailles et slot MIDDLE conservés. Les dangers/bouées/aides fixes
restent au slot TOP ; fond, texture, ports, courbes, signalements, GPS et
orientation ne sont pas désactivés. L'attribution existante expose modèle,
source, millésime, datum, DOI, licence et transformations. Le filtre et l'URL
versionnée empêchent l'éligibilité d'anciennes sondes au style MVP.

Ces constats proviennent de la lecture des couches et des tests Flutter avec
objets Mapbox simulés. **Aucune observation du rendu Android n'a été faite.**
Les éventuelles collisions entre slots, la stabilité perceptuelle au changement
de zoom, les chiffres près du trait de côte et la visibilité effective du GPS
restent à vérifier sur l'appareil.

## E. Tests et revues

Commandes exécutées à la racine, sauf Flutter dans `mobile` :

```bash
.venv/bin/python -m pytest -q
/home/palms/flutter/bin/flutter test --no-pub
/home/palms/flutter/bin/flutter analyze --no-pub
.venv/bin/ruff check <les fichiers Python du périmètre>
git diff --check
PYTHONPATH=backend .venv/bin/python backend/tools/probe_emodnet_depths.py
```

- État initial : **743 tests backend réussis** via `python -m pytest`, et 9
  tests Flutter ciblés réussis avant modifications.
- État final backend : **819 réussis**, 1 avertissement de dépréciation déjà
  présent concernant Starlette TestClient/httpx ; durée finale **3.79 s**.
- Nouveaux tests EMODnet : **76 cas**, tous hors connexion, clients simulés et
  CSV synthétiques créés en mémoire. Ils couvrent géographie, unités/signes,
  sentinelles et qualité, arrondi, MVT, sélection stable, limites, source unique,
  HTTP 4xx/5xx, timeout/échéance totale, corps trop gros, CSV invalide,
  déconnexion/annulation, débit/concurrence, cache RAM borné et stockage interdit.
- Flutter : **485 réussis**, environ 7 s, dont sources/styles/attribution,
  couches des autres familles et comportement en cas d'erreur des sources.
- `flutter analyze` : **aucun problème** ; Ruff et `git diff --check` : succès.

Échecs intermédiaires et corrections :

- L'invocation directe `.venv/bin/pytest` échouait à collecter deux tests
  préexistants (`backend` absent du chemin Python). L'invocation
  `.venv/bin/python -m pytest` résout ce problème sans modifier le projet.
- Un test supposait un centre sélectionné à la limite est malgré le stride ;
  son cas partiellement couvert a été corrigé. L'ancien test du seuil Z13 a
  été adapté au nouveau seuil Z12.
- Un test de route complet a révélé que le gestionnaire d'exceptions générique
  supprimait `Cache-Control` et le statut personnalisé des 503. Correction
  ciblée sur `/soundings`, sans changer les erreurs des autres endpoints.
- Un run intermédiaire combinant les nouveaux tests de route avec le cycle de
  vie global de l'application a fini avec deux échecs et un code de sortie 139.
  Les 76 tests isolés réussissaient. Les tests de route ont été alignés sur le
  modèle des tests API préexistants, sans déclencher le teardown global des
  pools de base de données ; la campagne finale complète termine en code 0.

Première revue manuelle, backend/données, distincte de l'exécution des tests :
relecture des constantes avec DDS/DAS reçus, ordre des axes, formule d'indices,
intervalles semi-ouverts, strides imbriqués, absence de tampon pour les centres,
contrôle des lignes CSV complètes, signes/LAT, sentinelles, qualité, plafond,
encodage, sélection de fournisseurs et fermeture des clients. Les réponses
réelles de huit régions ont été décodées et leurs signes/coordonnées vérifiés.

Deuxième revue manuelle, Flutter/MVP : relecture séparée des sources, filtres,
seuils, ordre d'installation, slots, collisions, attribution, erreurs, version
de contrat et `volatile`. Les autres couches gardent leurs identifiants et
sources. La lecture de l'API Dart installée confirme la propriété de cache local.
Ces revues ne sont pas des validations visuelles natives ni des revues par une
autre personne.

## F–G. Campagne réelle et performances

Huit appels **séquentiels**, une tuile Z14 avec de l'eau par région, via
`httpx.ASGITransport(app=app)` vers la route FastAPI réelle, runtime réel et
ERDDAP public réel. Sans démarrer un serveur, sans base, sans téléphone,
sans préchargement et sans test de charge. Toutes les réponses : HTTP 200,
statut `ok`, `no-store`, une requête ERDDAP chacune.

| Région | XYZ | Cellules demandées | Points MVT | CSV octets | MVT octets | Route ms | Exemples en m |
|---|---|---:|---:|---:|---:|---:|---|
| Toulon | 14/8463/6014 | 24 | 24 | 1378 | 5099 | 337.26 | 45.203075 ; 81 ; 40.2 |
| Marseille | 14/8433/6005 | 24 | 24 | 1390 | 5035 | 90.13 | 60.55 ; 58.25625 ; 56.5 |
| Ajaccio | 14/8587/6088 | 24 | 24 | 1421 | 5083 | 266.32 | 245.5 ; 306.15625 ; 375.4762 |
| Golfe de Gascogne | 14/8064/5828 | 18 | 18 | 1157 | 3879 | 252.56 | 115.14844 ; 115.05859 ; 114.64844 |
| Manche | 14/8121/5574 | 15 | 15 | 929 | 3297 | 288.74 | 48.4 ; 48.8 ; 48.3 |
| Mer du Nord | 14/8333/5448 | 15 | 15 | 1024 | 3383 | 248.73 | 20.766645 ; 20.125603 ; 19.337244 |
| Baltique | 14/8829/5166 | 15 | 15 | 904 | 3334 | 203.54 | 42.64 ; 41.77 ; 42.58 |
| Adriatique | 14/8829/5906 | 20 | 18 | 1236 | 3919 | 269.60 | 26.266876 ; 39.032814 ; 45.15531 |

Total : **155 cellules demandées, 153 points marins, 9439 octets CSV et
33029 octets MVT**. Les deux cellules non exploitables en Adriatique ont été
filtrées ; le résumé ne permet pas d'en attribuer individuellement la cause.
Les 153 élévations originales sont négatives, leurs profondeurs positives,
et les points décodés restent dans les BBOX des tuiles. Le parseur a aussi
vérifié l'alignement natif de toutes les coordonnées CSV demandées.

Exemple de coordonnées MVT décodées à Toulon : 5.954686°E, 43.088021°N,
45.203075 m, label « 45 ». La quantification MVT explique l'arrondi des coordonnées.

Les temps incluent réseau fournisseur, limitation de débit éventuelle,
normalisation, MVT et route ASGI ; ils ne mesurent ni une liaison mobile,
ni le rendu, ni le déploiement public. Les huit tuiles étaient distinctes,
sans lecture depuis un cache RAM chaud. Le résumé de mesure et quelques exemples
sont conservés hors dépôt ; aucun corps CSV/MVT brut n'est conservé.

La couverture testée ne certifie pas chaque cellule du rectangle européen,
chaque côte ou mer Noire/Égée/Arctique. Le mécanisme géographique fonctionne sur
la grille complète jusqu'à la limite Web Mercator, sans condition France/Toulon.

## H. Cache et stockage

Un client HTTP dédié évite entièrement le SQLite historique de `MarineHTTP`.
Aucun nouveau PostgreSQL, SQLite, CSV/XYZ, GeoTIFF, NetCDF, stockage objet ou
archive bathymétrique. Aucune dépendance ni migration de base ajoutée.
Les tests interdisent `open`, `io.open` et `sqlite3.connect` pendant un chargement
complet simulé. Le cache existant est uniquement RAM, 512 tuiles/32 Mio/300 s ;
son éviction et la déduplication concurrente ont été vérifiées.

Limites explicites : 2 connexions, 4 départs/s par processus, échéance fournisseur
10 s, HTTP 6 s, connexion/pool 2 s, corps décompressé 256 Kio, 64 cellules.
Les échecs ne deviennent pas des tuiles valides vides et ne sont pas cachés.
La route transmet `no-store`, y compris sur ses 503. La seule source Flutter de
chiffres est `volatile=true`, sans préchargement et avec un nouveau paramètre
de version pour les anciennes tuiles.

Le code Flutter ne contient pas de téléchargement offline des profondeurs.
Les configurations/propriétés sont auditées ; **l'absence effective d'écritures
par les composants natifs Mapbox/Android n'est pas démontrée sur appareil**.
Le proxy Nginx du dépôt n'active pas `proxy_cache`, mais le comportement de
l'infrastructure distante n'a pas été mesuré. Aucun cache existant n'a été effacé.

## I. Conservation et Git

Sauvegarde externe initiale :
`/home/palms/nowave-snapshots/emodnet-20261018T085611Z/`.

- `manifest.json` : SHA-256 des **693 fichiers** suivis/non suivis hors ignorés.
- `initial/` : copies des **16 fichiers suivis modifiés + 23 non suivis**.
- `diff.patch`, `cached.patch`, `status.txt`, `head.txt` : état initial.
- `final-manifest.json`, `final-status.txt`, `emodnet-changes.patch`,
  `integrity-summary.json` : comparaison finale et patch depuis l'état local initial.
- `shom-integrity.json` : empreintes initiales/finales complètes des dix chemins
  contenant « shom » ; **10/10 identiques**, incluant levés, manifeste, code,
  fixture et outil d'import. Les trois XYZ et le JSONL sont inchangés.
- `live-summary.jsonl` et `pytest-final.log` : résumés et preuve de test finale,
  sans réponse bathymétrique brute.

État final attendu et vérifié par le contrôle de clôture : **698 fichiers**,
toujours **16 fichiers suivis modifiés**, désormais **28 fichiers non suivis**.
Par rapport à l'initial : **11 fichiers existants modifiés, 5 nouveaux,
682 existants identiques, aucune suppression**. Parmi les 39 fichiers qui
contenaient déjà du travail local, 28 sont strictement identiques à l'initial ;
les onze autres ont les ajouts ciblés décrits en B. Le diff de staging reste vide.

Le HEAD et la branche n'ont pas changé. Aucun reset, clean, restore, rebase,
checkout de branche, commit, push ou PR. Les empreintes et le patch depuis
l'état initial permettent de relire séparément ce travail EMODnet du travail
hydrographique antérieur. Aucune donnée SHOM perdue.

## J. Verdict et validation restant sur Android

| Élément | Verdict | Portée |
|---|---|---|
| Backend EMODnet | **GO** | Fournisseur unique, erreurs distinctes, 76 cas dédiés et huit régions réelles |
| MVT | **GO** | Décodage réel et simulé, schéma compatible, indices/signes/propriétés/plafonds vérifiés |
| Affichage Flutter | **NON TESTÉ sur appareil** | Contrat/style testés, 485 tests réussis et analyse statique propre |
| Couverture européenne | **PARTIEL** | Huit régions réelles réussies ; aucune validation exhaustive du rectangle |
| Absence de stockage durable | **PARTIEL** | Backend GO et politiques Flutter explicites ; effet natif/distant non mesuré |
| Régression NoWave | **PARTIEL** | Suites backend/Flutter réussies et autres couches conservées ; régression visuelle/GPS appareil non testée |

Le MVP ne peut donc pas être déclaré entièrement validé sur Android.
Les profondeurs sont informatives, modélisées, **interdites pour la navigation
et la sécurité en mer**.

Tests précis à effectuer sur le téléphone, sans effacer ses données :

1. Avec une build contenant ces changements et le backend local à jour,
   ouvrir Toulon, Marseille puis Ajaccio ; vérifier l'apparition des chiffres
   dans l'eau à Z12, leur absence à Z11, puis Z13–16 et le surzoom Z17–18.
   Le surzoom doit agrandir les mêmes cellules sans créer de nouveaux points.
2. Déplacer doucement puis rapidement la carte et franchir des limites de
   tuiles ; vérifier stabilité, absence de doublons/basculements erratiques,
   lisibilité, collision des chiffres et progression de densité.
3. Vérifier les chiffres près de la côte et dans les ports ; relever toute
   position sur la terre actuelle. Le filtre d'élévation ne garantit pas un
   trait de côte moderne ni une précision à l'échelle d'un quai.
4. Vérifier que GPS/orientation, signalements, bouées, aides fixes, feux,
   phares, rochers/épaves/obstructions, ports et isobathes restent utilisables
   et que les chiffres ne masquent pas leurs icônes prioritaires.
5. Ouvrir l'attribution : modèle EMODnet DTM 2024, mètres/LAT, Consortium,
   DOI, CC BY 4.0, transformation NoWave et avertissement de navigation.
6. Passer successivement aux tuiles Gascogne, Manche, mer du Nord, Baltique et
   Adriatique listées ci-dessus, puis hors couverture européenne. Vérifier
   absence de chiffres ailleurs et conservation du fond/autres couches.
7. Provoquer une indisponibilité du seul fournisseur avec le backend de test
   (ou le désactiver via la configuration existante), observer les 503, puis
   rétablir. Aucun chiffre SHOM/NOAA ne doit réapparaître comme repli. Une panne
   ne doit pas masquer toute la carte ; ne pas attendre une alerte UI dédiée.
8. Vérifier fluidité et réseau pendant les déplacements. Confirmer, dans un
   environnement Android de développement, que la source de chiffres est
   volatile et que les nouvelles réponses ne sont pas stockées durablement.
   Un contrôle d'écritures natives est nécessaire pour lever cette réserve ;
   une simple visite offline ou la seule présence de `no-store` ne suffit pas.

Travail arrêté après implémentation locale, tests et rapport. Rien n'est publié.
