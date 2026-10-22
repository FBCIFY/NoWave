# Preuves NW-220 — gris marin et mosaïque

Collectées le 22 octobre 2026. Les photographies utilisateur de `mobile/codex_photo/` ne sont pas recopiées ni modifiées. `preserved-sha256.json` prouve l'identité des sept fichiers protégés.

## Comparaisons Android

- `before-gray.png` / `intermediate-A-gray.png` / `after-gray.png` : même caméra 5.934167 E,43.085278 N, Z16.3, cap 315°, pitch 45°. A correspond à `marine-visual-4`, la version finale à `marine-visual-7`.
- `before-pixels.png` / `intermediate-A-pixels.png` / `after-pixels.png` : même caméra 5.915 E,43.105 N, Z13.8, cap 0°, pitch 63.75°.
- `rejected-B5-dark-fringe.png` : essai bilinéaire rejeté avant normalisation du RGB associé à l'alpha. Ce n'est pas le rendu livré.
- `android-zooms.png`, `android-combined.png` : vignettes annotées des 23 captures ADB finales. Ce sont des planches de diagnostic, pas des images natives à la résolution d'origine. Grandes captures des comparaisons et d'autres terrains conservées séparément.
- `android-summary.json` : caméras effectivement appliquées, quantités rendues,26 IDs de courbes conservés, compteurs de requêtes/erreurs et état final de chaque capture.
- `runtime-style.json`, `api-final.json` : backend public marin local 8004, version 7 réellement utilisée ; source raster256 / maxzoom14 / LINEAR / MIDDLE.
- `attribution.png`, `attribution-ui.xml` : mention des couleurs d'affichage et de l'absence de mesure ajoutée, vérifiée dans le menu natif après défilement.
- `android-meminfo.txt`, `android-gfxinfo.txt` : mesures brutes finales, y compris les valeurs élevées de mémoire et les saccades. Aucune comparaison release ni mesure FPS Flutter/Mapbox globale n'en est déduite.
- `intermediate-budget-recheck.json` : contre-vérification d'un refus de budget vectoriel de la recette intermédiaire ; la recette finale repartie sur version 7 n'a enregistré aucune erreur marine.

## Pipeline raster exact

`tiles/<z>-<x>-<y>/` contient :

- `source.png` : réponse WMS **280×280** avec halo12, `interpolations=bilinear`. Les RGB associés du fournisseur sont conservés bruts dans ce fichier.
- `recolored-context.png` : normalisation du RGB associé, LUT, adoucissement et feather hérités ; le halo est encore présent.
- `water-context.png` : eau OSM, îles/jetées exclues, voisins réels nécessaires assemblés sur la grille XYZ.
- `final.png` : PNG256×256 de la couche visuelle, avec métadonnées de provenance de couverture.
- `metrics.json` : bbox/paramètres WMS, octets/temps, nombre de requêtes et de pixels reconstruits.

`NoWave.SourceCoverage` est le base64 compressé par le chunk texte PNG de 256×256 octets d'alpha **après les traitements de couverture hérités et le masque côtier, avant reconstruction de couleur**. Il ne représente ni un relevé de profondeur, ni un calcul d'exactitude hydrographique. Il est présent si des pixels ont été reconstruits ; sinon l'alpha final est déjà cette couverture. `NoWave.VisualFillPixels` compte aussi les pixels source partiellement transparents dont le fond visuel a été complété.

Rejeu sans réseau, réellement exécuté sur les dix entrées :

```sh
PYTHONPATH=backend .venv/bin/python docs/test-reports/artifacts/NW-220-gray-pixelation/replay_saved_tiles.py docs/test-reports/artifacts/NW-220-gray-pixelation/tiles
```

`adjacent-overlaps.json` compare les 24 pixels de halo communs : alpha identique sur 10 couples ;8 couples RGB exacts et 2 avec écart maximal 1/255 du fournisseur. Les tests synthétiques du dépôt vérifient l'égalité exacte pour des entrées identiques, y compris le prétraitement et la reconstruction combinés sur des découpages décalés.

## Mesures et reproduction native

`wms-interpolation.json`, `interpolation-metrics.json`, `initial-bilinear-seam.json`, `cpu-v7.json`, `cache-versions.json` et les journaux de `validation/` correspondent à de vraies exécutions. Les résultats rouges intermédiaires sont conservés avec les verts finaux.

Les scripts `capture_android.py`, `validate_android.py`, `audit_real_tiles.py`, `audit_wms_interpolation.py` gardent les paramètres de cette session (`/home/palms/NoWave`, ADB AV5PJV6328H03108, service VM local 8181, fichiers temporaires sous `/tmp`). Ils servent à reproduire la recette dans cet environnement ; la version Android nécessite un build debug réel et un backend local actif. Les scripts d'audit réseau ne sont pas des tests unitaires hors réseau.

Le téléphone utilise le backend local 8004 via `adb reverse`. Les services métier conservent leur URL habituelle ; le fichier privé `.env.json` est intact. Débrancher l'USB ou arrêter le backend peut rendre les sources marines locales indisponibles. Aucun déploiement n'a été réalisé.

## Provenance

[EMODnet Bathymetry](https://emodnet.ec.europa.eu/en/bathymetry), couche visuelle `emodnet:mean_multicolour`, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) ; couleurs transformées et continuité locale d'affichage par NoWave, sans nouvelle profondeur.

Masques dérivés des géométries Shortbread [© OpenStreetMap contributors](https://www.openstreetmap.org/copyright), [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/). Les coordonnées XYZ et grilles sont consignées dans les métadonnées. Les entrées source de l'audit côtier précédent restent également disponibles dans le dossier voisin `NW-220-coastal/`.
