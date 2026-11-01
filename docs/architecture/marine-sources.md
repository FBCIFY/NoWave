# Sources marines

Le backend choisit les fournisseurs selon la tuile demandée et leur couverture,
normalise les objets en WGS84, puis renvoie du GeoJSON ou du MVT. Le GPS et le
compte utilisateur n'interviennent pas dans ce choix.

Le mobile utilise les snapshots GeoJSON pour les ports, marques, courbes, sondes
et dangers. Les infrastructures portuaires restent en MVT ; la bathymétrie est
un raster PNG. Les [règles de chargement](marine-zoom-persistence.md) regroupent
les seuils de zoom et les budgets du mobile.

## Jeux intégrés et crédits

Les données sont sélectionnées, découpées ou recolorées par NoWave. Conserver
les crédits visibles et les licences lors d'une redistribution.

| Source | Utilisation | Licence et crédit |
| --- | --- | --- |
| GEBCO_2026 | Fond marin mondial, aperçu visuel échantillonné à 2 minutes d'arc | Domaine public, conditions GEBCO ; GEBCO Bathymetric Compilation Group 2026 |
| [EMODnet DTM 2024](https://doi.org/10.12770/cf51df64-56f9-4a99-b1aa-36b8d7b743a1) | Profondeurs modélisées en Europe | CC BY 4.0 ; EMODnet Bathymetry Consortium (2024) ; sélection, conversion de signe et arrondi NoWave |
| EMODnet contours 2022 et WMS bathymétrique | Courbes publiées et détail raster régional | CC BY 4.0 ; EMODnet Bathymetry Consortium, produit UE ; transformations NoWave |
| [Shom, balisage maritime](https://diffusion.shom.fr/donnees/balisage_maritime.html) | Bouées, balises et feux | Licence Ouverte 2.0 ; Shom, DOI 10.17183/DOI_BALISAGE_MARITIME |
| [Shom, épaves et obstructions 2022](https://diffusion.shom.fr/donnees/epaves.html) | Dangers ponctuels | CC BY-SA 4.0 ; Shom, DOI 10.17183/EPAVES_OBSTRUCTIONS ; dérivés sous la même licence |
| [IGN, BD TOPO](https://www.data.gouv.fr/datasets/bd-topo-r) | Ouvrages portuaires en service, édition WFS du 15 juin 2026 | Licence Ouverte 2.0 ; © IGN, BD TOPO ; transformations NoWave |
| [NOAA ENC Direct](https://nauticalcharts.noaa.gov/data/gis-data-and-services.html) | Marques, infrastructures, courbes, dangers ; sondes hors couverture EMODnet | CC0 1.0 ; NOAA Office of Coast Survey |
| [Open Waters Seamap](https://openwaters.io/charts/seamap) | Ports et marques issus d'OSM | CC BY 4.0 ; © Open Waters: Seamap et © OpenStreetMap contributors ; données OSM sous ODbL |
| [OpenStreetMap Shortbread](https://www.openstreetmap.org/copyright) | Infrastructures et masque côtier | ODbL 1.0 ; © OpenStreetMap contributors ; transformations NoWave |

Le registre `GET /api/v1/map/marine-sources` fournit les liens de produits,
licences et limites détaillées. Sa définition est dans
[sources.py](../../backend/app/infrastructure/marine/sources.py).
Les levés Shom archivés restent crédités mais ne fournissent plus les chiffres
de profondeur du mobile. CHS, AMSA, AHO et LINZ ne sont pas intégrés.

La base fusionnée contenant OSM est distribuée sous ODbL ; les obligations
propres aux autres apports restent attachées. Les métadonnées techniques ne
remplacent pas les crédits affichés sur la carte.

## Sélection et normalisation

Les couvertures Shom, NOAA et IGN servent au routage. Elles ne garantissent ni
l'exhaustivité des données ni une frontière juridique. Open Waters et Shortbread
restent les sources mondiales de leur famille, même lorsqu'une source nationale
est sélectionnée. Les sondes suivent une sélection distincte : EMODnet dans sa
couverture, NOAA ailleurs, sans bascule NOAA lors d'une panne EMODnet.

Chaque objet garde son identité source, sa géométrie, ses attributs, sa provenance
et sa licence. Une date de source NOAA (`SORDAT`) reste une date de source ; la
date de téléchargement ne devient pas une date de révision. Les coordonnées IGN
3D sont ramenées en 2D sans convertir l'altitude en profondeur.

Les attributs publiés déterminent les couleurs, catégories et systèmes IALA.
Une valeur inconnue reste inconnue. Le rapprochement utilise identité, attributs
compatibles et géométrie ; la proximité seule ne suffit pas. Un conflit conserve
les objets séparés. Les ports représentatifs Open Waters restent distincts des
ouvrages portuaires comme les quais et les digues.

## Routes publiques

Toutes les routes suivantes commencent par `/api/v1/map/` :

| Route | Contenu |
| --- | --- |
| `marine-features/{family}/{z}/{x}/{y}.geojson` | Snapshots WGS84 pour le mobile |
| `seamarks/{z}/{x}/{y}.pbf` | Marques, couche MVT `seamark` |
| `port-infrastructure/{z}/{x}/{y}.pbf` | Couche `port_infrastructure` et vues de rendu |
| `harbours/{z}/{x}/{y}.pbf` | Points de ports |
| `depth-contours/`, `soundings/`, `underwater-hazards/` + `{z}/{x}/{y}.pbf` | Couches hydrographiques |
| `bathymetry/{z}/{x}/{y}.png` | Détail bathymétrique régional |
| `marine-sources` | Crédits et limites des jeux |

`MARINE_API_BASE_URL` permet au mobile d'utiliser un backend marin distinct.
Sans cette variable, il conserve `API_BASE_URL`. Les requêtes marines sont
publiques, sans token Firebase. Les tuiles de signalements `/map/tiles/` restent
authentifiées sur la base principale.

`X-NoWave-Marine-Status` indique notamment `ok`, `degraded` ou `unavailable`.
Un succès signifie que la collecte a réussi, pas que la zone est exhaustive.
Une panne totale répond 503 avec `Cache-Control: no-store` et `Retry-After: 15`.
Elle ne remplace pas des données utiles par un faux résultat vide.

## Cache et réseau

| Niveau | Limite |
| --- | --- |
| HTTP vectoriel partagé | 12 requêtes actives, pool de 24 connexions, timeout 4 s ; connexion et pool 2 s |
| Collecte d'un fournisseur | Budget global 14 s, attente comprise |
| Cache HTTP SQLite | 512 Mio de corps, réponse limitée à 8 Mio |
| TTL fournisseurs | Shom/NOAA 6 h ; IGN/Open Waters 24 h ; OSM au moins 7 jours |
| Cache final GeoJSON/MVT en RAM | 512 entrées, 32 Mio ; TTL 300 s, 15 s si dégradé |
| Cache raster régional | 32 Mio en RAM, 128 Mio sur disque ; TTL 24 h |

Les sondes EMODnet et NOAA utilisent des clients sans cache disque de corps
numériques ; leurs réponses HTTP sortantes portent `no-store`. Le détail du
client EMODnet est dans [Profondeurs EMODnet](emodnet-depths.md).
Les erreurs fournisseur déclenchent une temporisation ; `Retry-After` est pris
en compte. Une annulation attend la fermeture HTTP avant de libérer sa place.
Les limites sont par processus : ajouter des workers multiplie la charge amont.

`MARINE_CACHE_DIR` vaut par défaut `~/.cache/nowave/marine`. En production, le
volume `marine-cache` est monté sur `/var/cache/nowave/marine`, avec le propriétaire
`10001:10001`. Conserver ensemble SQLite et ses fichiers WAL/SHM. Ne pas lancer
`docker compose down --volumes` sur l'installation persistante.
OSM impose un cache d'au moins sept jours, un User-Agent joignable et l'absence
de téléchargement massif ou de préchargement hors ligne.

## Raster et masque côtier

Le rendu `marine-visual-7` recolore le WMS EMODnet, puis applique le masque d'eau
OSM. La terre et les zones sans support restent transparentes. Une continuité
locale de couleur peut remplir de petits trous dans l'eau connue ; elle ne
produit aucune profondeur ni courbe.

Le champ PNG `NoWave.SourceCoverage` conserve l'alpha source lorsqu'un remplissage
a été appliqué. `NoWave.VisualFillPixels` et `X-NoWave-Raster-Usage` signalent
cette transformation. Une panne du masque central renvoie 503 ; un voisin
facultatif manquant laisse un rendu dégradé non mis en cache.

Ces données servent à l'affichage. Elles ne remplacent pas les cartes officielles
et ne permettent pas de calculer une marge sous quille.
