# Revue du remplacement du relief terrestre

**État historique avant la passe graphique suivante.** Les assertions d’assets inchangés
ci-dessous concernent uniquement le remplacement du DEM. Voir désormais
[VISUAL_REVIEW.md](VISUAL_REVIEW.md) pour le rendu, les assets modifiés et les tests actuels.

Branche `feat/NW-map-style`. Aucun commit ni push pour cette modification.
Le dossier non suivi `cartography/data/glo90/` était présent avant la demande et reste intact.

## Résultat

Source DEM : Mapzen/Tilezen, AWS Open Data, Terrarium 256 px. Hillshade natif
à exagération 0,15–0,22, atténué au dézoom. Palette terrestre inchangée.
Le générateur reste la source de vérité ; `style.json` a été régénéré.
Bathymétrie, GeoJSON nautique et sprites inchangés, contrôlés octet par octet
contre HEAD. Toutes les propriétés des couches préexistantes hors relief sont identiques.

L'île fictive à 0°/0° se situe réellement en mer : son remplissage couvre les
valeurs marines du DEM et reste plat. Le relief terrestre réel est testable
dans l'aperçu Marseille/Cassis (`--relief-preview --center 5.53 43.24 --zoom 12`).
Il ne déplace aucun objet fictif et n'affiche aucune bathymétrie à ces coordonnées.

## Tests

- Sept tests Python réussis (DEM, masques, caméra, provenance, remplacement de source, serveur).
- Six tests Flutter réussis ; `flutter analyze` sans erreur.
- Génération et validation des trois styles v8 réussies ; build Web réussi.
- Chromium : chargement DEM Mapzen réel, 71 réponses HTTP 200 dans les zones réelles,
  aucune erreur JS/MapLibre ; déplacement et zoom de la démo vérifiés.
- Captures comparées : 288 332 pixels marins opaques, aucun modifié par le hillshade.
- `git diff --check` réussi. Android/iOS physiques non exécutés ici.

## Captures

- [Cassis avant](previews/mapzen/cassis-before.png) / [après](previews/mapzen/cassis-after.png).
- [Marseille avant](previews/mapzen/marseille-before.png) / [après](previews/mapzen/marseille-after.png).
- [Démo précédente](previews/overview.png) / [démo après](previews/mapzen/demo-after.png).

Dans les zones réelles, « avant » signifie hillshade désactivé, « après » activé.

## Limites

Internet nécessaire pour le DEM tant qu'il n'est pas auto-hébergé. Aucun compte
AWS ni clé API. Notices d'attribution dans le style, le README et la page de crédits.
Le masque d'eau de l'aperçu est dérivé d'altitudes à z12 (≤0 m, fermeture de 3 pixels),
limité à l'emprise indiquée, approximatif et non utilisable comme littoral de référence.
Les pixels côtiers sont visibles à fort zoom. Les terres sous le niveau de la mer
nécessiteront un masque géographique réel. GLO-90/SRTM pourront être encodés en
Terrarium et substitués via `--relief-tiles` et `--relief-attribution`, sans changer
les couches visuelles ; adapter le masque si la géographie/DEM diffère.

## Fichiers modifiés, ajoutés ou supprimés

- `cartography/.dockerignore`
- `cartography/Dockerfile`
- `cartography/DATA_CONTRACT.md`
- `cartography/README.md`
- `cartography/assets/README.md`
- `cartography/assets/demo-relief.png`
- `cartography/assets/demo-sea-mask.png`
- `cartography/assets/mapzen-attribution.html`
- `cartography/assets/mapzen-preview-sea-mask.json`
- `cartography/assets/mapzen-preview-sea-mask.png`
- `cartography/package.json`
- `cartography/previews/mapzen/README.md`
- `cartography/previews/mapzen/cassis-after.png`
- `cartography/previews/mapzen/cassis-before.png`
- `cartography/previews/mapzen/demo-after.png`
- `cartography/previews/mapzen/marseille-after.png`
- `cartography/previews/mapzen/marseille-before.png`
- `cartography/previews/mapzen/pixel-check.json`
- `cartography/server.py`
- `cartography/style.json`
- `cartography/tests/test_relief.py`
- `cartography/tools/browser_relief.cjs`
- `cartography/tools/browser_smoke.cjs`
- `cartography/tools/build_style.py`
- `cartography/tools/check_relief_pixels.py`
- `cartography/tools/generate_demo.py`
- `cartography/tools/prepare_relief_masks.py`
- `cartography/tools/validate_style.cjs`
- `map_poc/README.md`
- `map_poc/lib/main.dart`
- `map_poc/lib/map_style.dart`
- `map_poc/test/map_style_test.dart`

Ce document de revue est également ajouté.
