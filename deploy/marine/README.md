# Fond marin GEBCO

`gebco-2026-v2.tar.gz` contient 5 461 tuiles WebP de 256 px, Z0–6, et leur
manifeste. Le build vérifie le checksum puis les extrait dans l'image web ;
Nginx les sert avec un an de cache, sans appel fournisseur au démarrage.

Source : GEBCO Bathymetric Compilation Group 2026, *The GEBCO_2026 Grid*,
[DOI](https://doi.org/10.5285/4f68d5c7-45eb-f999-e063-7086abc036fa).
Domaine public, avec crédit et respect des
[conditions GEBCO](https://www.gebco.net/data-products/gridded-bathymetry/terms-of-use).
NoWave échantillonne une cellule sur huit, soit deux minutes d'arc, et recolore
le fond. Terres et pixels côtiers incertains restent transparents. Cet aperçu
mêle mesures et interpolations et ne sert pas à la navigation.

## Régénérer

Depuis la racine, avec les dépendances de `backend/requirements.lock` :

```sh
python backend/tools/prepare_gebco_background.py \
  /tmp/gebco-2026-stride8.dods /tmp/gebco-2026-tid-stride8.dods \
  deploy/marine/gebco-2026-v2.tar.gz --download
(cd deploy/marine && shasum -a 256 gebco-2026-v2.tar.gz > gebco-2026-v2.tar.gz.sha256)
```

L'outil vérifie les sous-ensembles téléchargés, environ 279 Mio au total.
Contrôler le rendu et `backend/tests/unit/test_gebco_background.py` avant de
valider l'archive et son checksum. Une autre version de Pillow/libwebp peut
modifier les octets compressés.

Une modification de source ou palette exige une nouvelle version d'URL.
Conserver les anciennes archives et URL immuables pour les clients installés.
