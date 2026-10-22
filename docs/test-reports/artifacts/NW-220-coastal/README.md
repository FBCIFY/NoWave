# Preuves locales NW-220 — artefacts côtiers

Collectées le 22 octobre 2026, Europe/Paris, sur la branche locale autorisée.
Les photos de référence et fichiers utilisateur ne sont pas modifiés.

- `before-normal.png` / `after-saint-mandrier.png` : même caméra, point de reproduction fourni, Z15.3, cap 0°, inclinaison 45°.
- `before-photo-area.png` / `after-photo-area.png` : mêmes ouvrages que la photo initiale, autre cadrage documenté : 5.927° E, 43.109° N, Z15.3, cap 0°, inclinaison 63.75°.
- `before-no-raster.png`, `before-no-docks-relief.png` et `probe-neutral-water.png` : expériences temporaires avant correction ; style restauré après.
- `pipeline-photo-area.png` : cinq mosaïques alignées couvrant Z14 x8461–8462 / y6012–6013. Blanc dans le panneau source = transparence, pas une profondeur.
- `tiles/14-*/source-padded.png` : octets PNG EMODnet WMS 262×262 avec halo 3 px ; `metrics.json` conserve tous les paramètres WMS et la bbox. `coast.mvt` = réponse Shortbread brute ; `mask.png`, `final.png` = produits du code backend existant. Les fichiers supplémentaires sont des dérivés de diagnostic.
- `counteraudit.json`, `tile-metrics.json`, `adjacent-source-overlaps.json` : mesures exactes et comparaison des zones communes aux tuiles.
- `pixel-comparison.json` : indicateur visuel sRGB dans deux régions fixes. Les seuils comptent aussi certains symboles cartographiques ; ce n'est ni une classification de profondeur, ni un masque de vérité terrestre.
- `before-style.json` / `after-style.json` : contrat de rendu natif pertinent, sans les gros contenus GeoJSON. Sources identiques ; seule l'attribution du raster change. Le fond océanique utilise désormais une expression de zoom.
- `android-summary.json`, `android-contours.json`, captures `after-*` et `android-contact-sheet.png` : véritables captures ADB et requêtes du moteur natif ; aucune image de rendu n'est générée par IA.
- `after-attribution.png` : légende du fond gris visible dans le menu natif.
- `validation/` : sorties des commandes, y compris l'échec Flutter initial et le résumé des erreurs initiales de configuration PostGIS.
- `preserved-files-sha256.json` : égalité des empreintes des cinq fichiers utilisateur avant et après.

## Rejouer les diagnostics de tuiles hors réseau

Depuis la racine du dépôt, avec son environnement Python existant :

```sh
PYTHONPATH=backend .venv/bin/python docs/test-reports/artifacts/NW-220-coastal/audit_tiles.py docs/test-reports/artifacts/NW-220-coastal/tiles
PYTHONPATH=backend .venv/bin/python docs/test-reports/artifacts/NW-220-coastal/counteraudit_tiles.py docs/test-reports/artifacts/NW-220-coastal/tiles
```

Ces deux commandes ont été réellement rejouées avec les dix couples d'entrées conservés. Avec ces entrées présentes, elles ne téléchargent rien. La première régénère les dérivés de diagnostic. Si les entrées sont supprimées, le premier script peut télécharger des tuiles publiques : conserver les entrées pour un rejeu strictement hors réseau.

Les scripts Android conservent les paramètres de cette session (appareil `AV5PJV6328H03108`, service VM local port 8181, journaux sous `/tmp/`). Ils utilisent le diagnostic debug existant de `lib/main.dart` et `mobile/tool/nw220_device_validation.py`. Ils nécessitent un build debug de la version à vérifier, une connexion ADB et un service VM actif. Les modes `baseline` correspondent au code avant correctif ; leur nom n'autorise pas à présenter un rendu corrigé comme un rendu antérieur.

## Provenance des données

PNG de la couche `emodnet:mean_multicolour` : [EMODnet Bathymetry](https://emodnet.ec.europa.eu/en/bathymetry), produit visuel, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), transformations de palette et transparence NoWave conservées dans les dérivés.

Géométries Shortbread : [© OpenStreetMap contributors](https://www.openstreetmap.org/copyright), [ODbL](https://opendatacommons.org/licenses/odbl/1-0/), URL d'origine `https://vector.openstreetmap.org/shortbread_v1/{z}/{x}/{y}.mvt`. Les entrées brutes sont conservées pour éviter des téléchargements répétés et permettre l'examen hors réseau.
