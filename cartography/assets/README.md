# Assets NoWave

`demo-bathymetry.png` et `../data/demo.geojson` :
**entièrement synthétiques**, île fictive centrée sur 0°/0°. Aucune valeur
nautique réelle. Générés par `tools/generate_demo.py`, pas de source géographique.

Sprites : créations géométriques originales NoWave, générées par le même script.
Les couleurs des balises et marques de sommet suivent les conventions demandées.
Les textures sont volontairement discrètes. Atlases 1× et 2×.

Police : Open Sans Semibold, glyphes 0–255, 256–511 et 8192–8447
précompilés issus de
`https://demotiles.maplibre.org/font/Open%20Sans%20Semibold/{range}.pbf`
(licence SIL OFL, copie dans `font/OFL.txt`). Les deux plages supplémentaires
couvrent les noms géographiques régionaux et leur ponctuation ; toutes sont
servies localement, sans nouvelle dépendance réseau au rendu. Pour d'autres langues, fournir les plages PBF nécessaires
avec les licences correspondantes sur le même serveur.

Relief : tuiles réelles externes Mapzen/AWS, chargées depuis Internet.
`demo-relief.png` a été supprimé ; il n'est plus généré.
`demo-sea-mask.png` reprend les RGB du raster bathymétrique sans les modifier
et rend les terres fictives transparentes, pour recouvrir le hillshade dans l'eau.
`mapzen-preview-sea-mask.png` est un masque de diagnostic eau/terre dérivé du DEM
réel ; méthode et emprise dans le JSON associé. Les pixels du DEM ne sont pas
modifiés. `mapzen-attribution.html` publie les crédits des producteurs Tilezen.
Régénération des masques : `tools/prepare_relief_masks.py` (Pillow, Internet).

Passe graphique : raster DEMO 2048 px, profondeur continue synthétique ; contours
calculés sur ce champ, puis lissés/simplifiés. NumPy sert uniquement à la génération.
`generate_demo.py` régénère également le masque fictif sans connexion Internet.
