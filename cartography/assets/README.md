# Assets NoWave

`demo-bathymetry.png`, `demo-relief.png` et `../data/demo.geojson` :
**entièrement synthétiques**, île fictive centrée sur 0°/0°. Aucune valeur
nautique réelle. Générés par `tools/generate_demo.py`, pas de source géographique.

Sprites : créations géométriques originales NoWave, générées par le même script.
Les couleurs des balises et marques de sommet suivent les conventions demandées.
Les textures sont volontairement discrètes. Atlases 1× et 2×.

Police : Open Sans Semibold, glyphes 0–255 précompilés issus de
https://demotiles.maplibre.org/font/Open%20Sans%20Semibold/0-255.pbf
(licence SIL OFL, copie dans `font/OFL.txt`). Les textes de démo restent dans
cette plage Unicode. Pour d'autres langues, fournir les plages PBF nécessaires
avec les licences correspondantes sur le même serveur.

Aucun appel externe nécessaire pendant l'affichage de la démo.
