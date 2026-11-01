# Fixtures marines

Extraits réels collectés du 16 au 18 octobre 2026 pour des tests sans réseau.
Données de test, pas de navigation.

| Fichiers | Source et licence |
| --- | --- |
| `shom.json` | Balisage Shom, Licence Ouverte 2.0 |
| `noaa.json` | NOAA ENC Direct, CC0 |
| `ign.json` | © IGN BD TOPO, édition WFS 2026-06-15, Licence Ouverte 2.0 |
| `openwaters.pbf` | © Open Waters Seamap, CC BY 4.0 ; © contributeurs OpenStreetMap, ODbL |
| `shortbread.pbf`, `coastline-real.json` | © contributeurs OpenStreetMap, ODbL 1.0 |
| `port-merge.json` | © IGN BD TOPO, édition WFS 2026-06-15, Licence Ouverte 2.0 ; © contributeurs OpenStreetMap, ODbL |
| `fixed-aids.json`, `seamarks-coast-audit.json` | Balisage Shom, Licence Ouverte 2.0 ; NOAA ENC Direct, CC0 |
| `hydrography-real.json` | NOAA, CC0 ; épaves/obstructions Shom, CC BY-SA 4.0 ; produit UE EMODnet, CC BY 4.0 |

Lors d’un remplacement, garder la géométrie, les attributs source et les crédits.
Les PBF utilisent un extent de 4096 et un axe Y vers le nord au décodage.
Les cas synthétiques restent dans les tests Python.

Sources : [Shom](https://diffusion.shom.fr/donnees/balisage_maritime.html)
(DOI `10.17183/DOI_BALISAGE_MARITIME`),
[NOAA](https://repository.library.noaa.gov/view/noaa/71555),
[IGN](https://www.data.gouv.fr/datasets/bd-topo-r),
[Seamap](https://github.com/openwatersio/seamap),
[OpenStreetMap](https://www.openstreetmap.org/copyright).
Les sources hydrographiques sont détaillées dans [le guide dédié](../../../../docs/architecture/hydrography.md).
