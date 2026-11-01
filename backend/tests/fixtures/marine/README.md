# Fixtures marines

Extraits réels de fournisseurs, collectés du 16 au 18 octobre 2026 et réduits aux
objets utiles aux tests. Les tests les lisent sans appel réseau. Ces données de
test ne servent pas à la navigation.

| Fichier | Source et contenu | Licence et attribution |
| --- | --- | --- |
| `shom.json` | Balisage Shom WFS : bouées, balise cardinale et voyants liés ; zone `5.85,43.04,6.0,43.15` | Shom, Licence Ouverte 2.0 |
| `noaa.json` | NOAA ENC Direct : bouée et construction littorale ; zone `-80.2,25.73,-80.1,25.83` | NOAA, CC0 |
| `ign.json` | Cinq quais IGN BD TOPO WFS, coordonnées 3D d’origine | © IGN BD TOPO, édition WFS 2026-06-15, Licence Ouverte 2.0 |
| `openwaters.pbf` | Tuile Seamap `12/2115/1503` réduite aux classes de bouées et à une balise cardinale | © Open Waters: Seamap, CC BY 4.0 ; © contributeurs OpenStreetMap, ODbL |
| `shortbread.pbf` | Tuile OSM Shortbread `12/2115/1503` réduite aux objets des trois couches portuaires | © contributeurs OpenStreetMap, ODbL |
| `port-merge.json` | Quatre paires réelles IGN/OSM normalisées pour tester la fusion et la conservation des provenances | © IGN BD TOPO, édition WFS 2026-06-15, Licence Ouverte 2.0 ; © contributeurs OpenStreetMap, ODbL |
| `fixed-aids.json` | Balises, phares, feux et amers Shom/NOAA, dont des cas IALA B | Shom, Licence Ouverte 2.0 ; NOAA, CC0 |
| `hydrography-real.json` | Sondes et dangers NOAA, épaves et obstructions Shom, courbes EMODnet | NOAA, CC0 ; Shom, CC BY-SA 4.0 ; produit UE EMODnet, CC BY 4.0 |
| `coastline-real.json` | Polygones `ocean` OSM Shortbread des tuiles `6/33/23`, `9/264/187`, `12/2116/1503` | © contributeurs OpenStreetMap, ODbL 1.0 |
| `seamarks-coast-audit.json` | 22 objets Shom/NOAA avec géométrie d’origine, source et propriétés normalisées attendues | Shom, Licence Ouverte 2.0 ; NOAA ENC Direct, CC0 |

Les PBF gardent les coordonnées locales de tuile, un extent de 4096 et l’axe Y
orienté vers le nord au décodage. Les identifiants Shortbread désignent des
fragments de tuile. La normalisation des paires IGN/OSM retire uniquement
l’altitude IGN et convertit les coordonnées en WGS84.

Les cas rares d’aides fixes comprennent Caye Ronde en Martinique (Shom `bcnisd`)
et Buttonwood Harbor (NOAA, couche 2). Un test unitaire déplace une copie d’objet
pour vérifier l’encodage ; cette copie n’est pas utilisée comme fixture
d’intégration. Les cas synthétiques restent dans les tests Python.

## Sources et crédits

- [Shom — balisage maritime](https://diffusion.shom.fr/donnees/balisage_maritime.html),
  DOI `10.17183/DOI_BALISAGE_MARITIME`.
- [NOAA — données ENC et licence CC0](https://repository.library.noaa.gov/view/noaa/71555).
- [IGN — BD TOPO et Licence Ouverte 2.0](https://www.data.gouv.fr/datasets/bd-topo-r).
- [Open Waters Seamap](https://github.com/openwatersio/seamap) et
  [crédits OpenStreetMap](https://www.openstreetmap.org/copyright).
- [Contrats et sources hydrographiques](../../../../docs/architecture/hydrography.md).
