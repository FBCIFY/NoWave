# Preuves historiques NW-220 — audit côtier

Recette du 22 octobre 2026, avant la reconstruction locale de couleur. Le rendu courant est documenté dans [l'audit final](../../NW-220-gray-water-and-pixelation-review.md).

La sélection conserve :

- `before-photo-area.png` / `after-photo-area.png` : même caméra, 5.927° E, 43.109° N, Z15.3, cap 0°, pitch 63.75°. Le gris de cette étape historique a ensuite été traité par le correctif final.
- `pipeline-photo-area.png` : source, alpha, masque côtier et composites alignés ; le blanc du panneau source représente la transparence.
- `tile-metrics.json`, `counteraudit.json`, `adjacent-source-overlaps.json` : mesures des dix entrées historiques et des treize raccords, sans reproduire les centaines de dérivés.
- `pixel-comparison.json` : indicateur visuel, sans interprétation en profondeur.
- `preserved-files-sha256.json` : empreintes des fichiers utilisateur protégés à cette étape.

Les autres captures, PNG/MVT et journaux générés ont été retirés du diff par un commit normal. Leur inventaire détaillé (taille, rôle, nécessité, décision et empreinte) est [conservé ici](../../NW-220-PR125-evidence-inventory.csv). Les fichiers utilisateur non suivis ne sont pas concernés.

## Reproduction

Les tests automatisés ne dépendent d'aucun de ces fichiers. La paire bilinéaire adjacente et le rejeu du pipeline **courant** sont dans [le dossier final](../NW-220-gray-pixelation/README.md).

Pour reproduire spécifiquement le diagnostic historique avec son code historique, extraire une archive dans un dossier temporaire distinct, sans changer de branche ni réécrire l'historique :

```sh
proof_dir=$(mktemp -d /tmp/nowave-coastal-history.XXXXXX)
git archive 433c7bad backend docs/test-reports/artifacts/NW-220-coastal | tar -x -C "$proof_dir"
PYTHONPATH="$proof_dir/backend" .venv/bin/python "$proof_dir/docs/test-reports/artifacts/NW-220-coastal/audit_tiles.py" "$proof_dir/docs/test-reports/artifacts/NW-220-coastal/tiles"
PYTHONPATH="$proof_dir/backend" .venv/bin/python "$proof_dir/docs/test-reports/artifacts/NW-220-coastal/counteraudit_tiles.py" "$proof_dir/docs/test-reports/artifacts/NW-220-coastal/tiles"
```

Les dix entrées de cette archive permettent le rejeu hors réseau ; ne pas supprimer leurs PNG/MVT avant de lancer les scripts. L'archive est disponible dans l'historique Git, pas dans un artefact Actions à rétention limitée.

Les nouveaux résultats volumineux sont publiés par `NoWave CI` : `python-test-results`, `flutter-test-results`, `database-test-results`, `web-test-results` et `nowave-production-validation-<SHA>` (rétention 14 jours). Les rapports finaux restent versionnés.

## Provenance

[EMODnet Bathymetry](https://emodnet.ec.europa.eu/en/bathymetry), `emodnet:mean_multicolour`, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), palette et transparence transformées par NoWave ; aucune profondeur ajoutée.

Géométries Shortbread : [© OpenStreetMap contributors](https://www.openstreetmap.org/copyright), [ODbL](https://opendatacommons.org/licenses/odbl/1-0/). Les entrées brutes historiques sont récupérables avec l'archive ci-dessus.
