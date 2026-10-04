# Aperçus de relief réel

Cassis : 5,53 / 43,205 ; La Ciotat : 5,605 / 43,174 ; Marseille : 5,37 / 43,30.
Zoom 12, même caméra pour chaque paire avant/après hillshade.
DEM réel Mapzen/AWS, mer unie, aucune bathymétrie ni objet nautique de démo.
Le masque littoral dérivé du DEM reste approximatif et doit être remplacé.

`pixel-check.json` : 815760 pixels de mer opaque inchangés dans les trois zones.
Le contrôle exclut l'interface et les 24 px du contrôle d'attribution, qui change
lorsque le DEM est masqué. Il ne vérifie pas l'exactitude du trait de côte.
`browser-result.json` : chargement CDN réel, 116 réponses DEM réussies, aucune erreur.
`demo-after.png` conserve la scène fictive de la passe Mapzen précédente.

Voir [la revue graphique actuelle](../../VISUAL_REVIEW.md) et les six scénarios.
