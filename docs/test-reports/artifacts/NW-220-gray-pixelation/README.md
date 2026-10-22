# Preuves finales NW-220 — gris marin et mosaïque

Recette Android et backend du 22 octobre 2026, version `marine-visual-7`. Les photographies utilisateur et `docs/design/` restent exclus du suivi et inchangés ; `preserved-sha256.json` contient les sept empreintes protégées.

## Sélection pour la revue

- `before-gray.png` / `after-gray.png` : même caméra 5.934167 E, 43.085278 N, Z16.3, cap 315°, pitch 45° ; digue conservée, plage grise marine corrigée.
- `before-pixels.png` / `after-pixels.png` : même caméra 5.915 E, 43.105 N, Z13.8, cap 0°, pitch 63.75° ; comparaison de la mosaïque.
- `android-zooms.png` et `android-combined.png` : planches annotées des 23 captures finales, comprenant second port, côte naturelle, pleine eau, courbes offshore, déplacements et reload. Ces vignettes ne remplacent pas les grandes comparaisons avant/après ci-dessus.
- `attribution.png` : mention native des couleurs locales d'affichage, sans mesure ajoutée.
- `android-summary.json`, `runtime-style.json`, `api-final.json` : caméras, compteurs, identifiants de courbes, raster256/maxzoom14/LINEAR/MIDDLE et version réellement utilisés.
- `android-meminfo.txt`, `android-gfxinfo.txt`, `cpu-v7.json` : coûts et limites de performance mesurés, sans prétendre à une comparaison release.
- `intermediate-budget-recheck.json` : incident vectoriel intermédiaire et contre-vérification ; le rapport explique cet incident, distinct du parcours final sans erreur.
- `adjacent-overlaps.json`, `interpolation-metrics.json`, `wms-interpolation.json`, `cache-versions.json`, `gray-screen-indicator.json` : synthèses des mesures historiques complètes.

L'[inventaire exhaustif](../../NW-220-PR125-evidence-inventory.csv) distingue les 43 preuves conservées parmi les 272 fichiers initiaux. Les captures intermédiaires, vues individuelles déjà couvertes par les planches, journaux/JUnit et PNG/MVT redondants ont été retirés du diff. Ils restent récupérables au [SHA initial de la PR](https://github.com/FBCIFY/NoWave/tree/f5e4527bd730dbda8ce6f716d941a32841f5f6f6/docs/test-reports/artifacts). Aucun historique n'a été réécrit.

## Rejeu exact du pipeline courant

Deux tuiles adjacentes **14/8461/6014 et 14/8462/6014** conservent chacune quatre fichiers : `source.png` (WMS bilinéaire280 avec halo12), `water-context.png` (eau OSM avec ouvrages exclus), `final.png` (sortie256 avec métadonnées de couverture), `metrics.json` (paramètres et coûts de collecte).

```sh
PYTHONPATH=backend .venv/bin/python docs/test-reports/artifacts/NW-220-gray-pixelation/replay_saved_tiles.py docs/test-reports/artifacts/NW-220-gray-pixelation/tiles
```

Le script recalcule les pixels et vérifie l'identité avec le résultat enregistré, l'identité de la couverture source et la borne d'alpha par le masque d'eau. Il n'a besoin d'aucun réseau. La paire sélectionnée couvre la zone de gris et un raccord côtier ; les tests synthétiques couvrent notamment les quatre coins, l'abstention et les cumuls de filtres. Les métriques historiques sur dix tuiles ne sont pas présentées comme deux nouvelles mesures.

`NoWave.SourceCoverage` conserve exactement les octets alpha après feather/masque hérités, **avant** reconstruction visuelle. L'alpha d'affichage peut augmenter localement ; aucune profondeur mesurée n'est créée. Sans reconstruction, l'alpha final est déjà cette couverture. Les fichiers `recolored-context.png` dérivés sont recalculés par le script et n'ont plus besoin d'être versionnés.

Pour rejouer les dix entrées originales, les extraire du commit `f5e4527b` avec `git archive` dans un répertoire temporaire, puis passer son dossier `tiles` au même script. La conservation des verrous de dépendances permet de reproduire l'environnement ; les versions locales/CI différentes sont documentées dans le rapport final.

## Recette native et résultats CI

`capture_android.py`, `validate_android.py`, `audit_real_tiles.py` et `audit_wms_interpolation.py` gardent les paramètres de collecte. Adapter chemin du dépôt, appareil ADB, port du service VM et dossiers temporaires à l'environnement. La recette Android exige un vrai build debug et un backend marin local ; les audits réseau sont distincts du rejeu hors réseau. La recette initiale utilisait le backend8004 via `adb reverse`, sans modifier le fichier privé `.env.json` ni déployer le correctif.

Les nouveaux journaux, JUnit, couverture et rapports Trivy sont déjà publiés par `NoWave CI` sous les noms `python-test-results`, `flutter-test-results`, `database-test-results`, `web-test-results`, `nowave-production-validation-<SHA>` (14 jours). Les rapports finaux et cette sélection restent dans Git. Les anciens journaux retirés restent accessibles au SHA initial, y compris les échecs intermédiaires expliqués dans le rapport.

## Provenance

[EMODnet Bathymetry](https://emodnet.ec.europa.eu/en/bathymetry), `emodnet:mean_multicolour`, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), couleurs transformées par NoWave, sans nouvelle profondeur.

Masques dérivés de Shortbread [© OpenStreetMap contributors](https://www.openstreetmap.org/copyright), [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/). Coordonnées et paramètres d'origine conservés dans les métadonnées.
