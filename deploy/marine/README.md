# Fond marin mondial GEBCO

`gebco-2026-v2.tar.gz` contient 5 461 tuiles WebP de 256 px, de Z0 à Z6,
et leur manifeste de provenance. Le build vérifie leur checksum puis les extrait
dans l'image web. Nginx les sert directement sous
`/api/v1/map/seafloor/gebco-2026-v2/{z}/{x}/{y}.webp`, avec un an de cache.
Le rendu ne dépend pas de l'API ni d'un fournisseur externe au démarrage.

Le mobile charge d'abord une tuile parente, conserve les tuiles sur disque et
superpose le détail EMODnet à partir de Z5, après 600 ms d'attente. Hors de
l'emprise EMODnet, seul GEBCO est demandé. Les zones transparentes régionales
laissent voir le fond mondial.

## Source et précision

GEBCO Bathymetric Compilation Group 2026, *The GEBCO_2026 Grid* :
[jeu de données](https://doi.org/10.5285/4f68d5c7-45eb-f999-e063-7086abc036fa).
Domaine public, avec attribution et respect des
[conditions GEBCO](https://www.gebco.net/data-products/gridded-bathymetry/terms-of-use).

Le fond échantillonne une cellule sur huit de la grille native de 15 secondes
d'arc : deux minutes d'arc, environ 3,7 km nord–sud. Il donne une vue d'ensemble,
sans détail portuaire, sonde ni courbe dérivée. L'agrandissement n'ajoute aucune
donnée. GEBCO mêle mesures et interpolations : l'espacement de la grille ne
garantit pas une précision uniforme. Ces données ne servent pas à la navigation
ni à la sécurité en mer.

Les altitudes positives et les terres identifiées par TID restent transparentes,
y compris les terres sèches sous le niveau marin. Le masque exclut les pixels
côtiers incertains et utilise un halo d'un pixel pour raccorder les tuiles.
Le trait de côte peut différer du fond Mapbox.

## Régénérer les tuiles

Utiliser l'environnement Python de `backend/requirements.lock`. Depuis la racine :

```sh
python backend/tools/prepare_gebco_background.py \
  /tmp/gebco-2026-stride8.dods /tmp/gebco-2026-tid-stride8.dods \
  deploy/marine/gebco-2026-v2.tar.gz --download
cd deploy/marine
sha256sum gebco-2026-v2.tar.gz > gebco-2026-v2.tar.gz.sha256
```

L'outil vérifie le SHA-256 des sous-ensembles téléchargés, environ 223 Mio
pour les altitudes et 56 Mio pour la classification. Ces fichiers temporaires
restent hors de Git. Une autre version de Pillow/libwebp peut modifier les octets
compressés : contrôler le rendu avant de mettre à jour le checksum.

Une modification de source ou de palette exige une nouvelle version d'URL pour
renouveler les caches. Vérifier `backend/tests/unit/test_gebco_background.py`
et les tests du contrôleur mobile. Conserver l'archive v1 et ses URL immuables
pour les anciens clients.
