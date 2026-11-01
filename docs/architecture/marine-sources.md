# Sources marines

Le backend choisit les fournisseurs selon la tuile et leur couverture, sans
utiliser le GPS ou le compte. Il conserve identité, provenance et attributs
publiés ; une valeur inconnue reste inconnue. Une fusion exige une identité,
des attributs et une géométrie compatibles. La proximité seule ne suffit pas.

## Jeux et licences

| Source | Contenu utilisé | Licence et crédit |
| --- | --- | --- |
| GEBCO_2026 | Fond marin mondial | Domaine public, conditions GEBCO ; GEBCO Bathymetric Compilation Group 2026 |
| [EMODnet DTM 2024](https://doi.org/10.12770/cf51df64-56f9-4a99-b1aa-36b8d7b743a1) | Profondeurs modélisées | CC BY 4.0 ; EMODnet Bathymetry Consortium (2024) |
| EMODnet contours 2022 et WMS | Courbes et détail raster | CC BY 4.0 ; EMODnet Bathymetry Consortium, produit UE |
| [Shom, balisage](https://diffusion.shom.fr/donnees/balisage_maritime.html) | Bouées, balises, feux | Licence Ouverte 2.0 ; Shom, DOI 10.17183/DOI_BALISAGE_MARITIME |
| [Shom, épaves et obstructions 2022](https://diffusion.shom.fr/donnees/epaves.html) | Dangers ponctuels | CC BY-SA 4.0 ; Shom, DOI 10.17183/EPAVES_OBSTRUCTIONS |
| [IGN, BD TOPO](https://www.data.gouv.fr/datasets/bd-topo-r) | Ouvrages portuaires en service | Licence Ouverte 2.0 ; © IGN, BD TOPO, édition WFS du 15 juin 2026 |
| [NOAA ENC Direct](https://nauticalcharts.noaa.gov/data/gis-data-and-services.html) | Marques, ouvrages, courbes, dangers et sondes | CC0 1.0 ; NOAA Office of Coast Survey |
| [Open Waters Seamap](https://openwaters.io/charts/seamap) | Ports et marques OSM | CC BY 4.0 ; © Open Waters: Seamap et © OpenStreetMap contributors ; OSM sous ODbL |
| [OpenStreetMap Shortbread](https://www.openstreetmap.org/copyright) | Ouvrages et masque côtier | ODbL 1.0 ; © OpenStreetMap contributors |

NoWave sélectionne, découpe ou recolore ces données. Conserver les crédits
visibles, la mention des transformations et les licences lors d'une redistribution.
La base fusionnée contenant OSM reste sous ODbL ; les dérivés Shom d'épaves et
obstructions restent sous CC BY-SA 4.0.

Le registre `marine-sources` expose les liens de produits, licences et limites ;
voir les [contrats API](../API.md). Il est défini dans
[sources.py](../../backend/app/infrastructure/marine/sources.py).
Les levés Shom archivés ne fournissent plus les chiffres affichés. CHS, AMSA,
AHO et LINZ ne sont pas intégrés. Les couvertures restent celles des fournisseurs,
sans garantie d'exhaustivité.

## Configuration et cache

Configuration de l’app : [guide mobile](../../mobile/README.md).

Le cache HTTP SQLite utilise `MARINE_CACHE_DIR`, par défaut
`~/.cache/nowave/marine`. En production, le volume `marine-cache` est monté sur
`/var/cache/nowave/marine`, propriétaire `10001:10001`. Conserver SQLite et ses
fichiers WAL/SHM ensemble ; ne pas supprimer les volumes de production.

OSM demande un cache d'au moins sept jours, un User-Agent joignable et aucun
téléchargement massif ou préchargement hors ligne. Les clients numériques
EMODnet et NOAA ne stockent pas leurs corps de réponse sur disque. Les limites
réseau sont par processus : ajouter des workers multiplie les appels amont.

## Raster côtier

Le WMS EMODnet est recoloré puis limité à l'eau par le masque OSM. Une continuité
locale de couleur peut combler de petits trous : elle ne crée aucune profondeur.
Le PNG conserve la couverture d'origine dans `NoWave.SourceCoverage` lorsqu'un
remplissage est appliqué ; `NoWave.VisualFillPixels` signale les pixels ajoutés.
Les terres et les zones sans support restent transparentes.
