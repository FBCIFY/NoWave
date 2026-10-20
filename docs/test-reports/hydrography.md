# Validation hydrographie — 17 octobre 2026

Implémentation locale sans commit. Les courbes apparaissent réellement à Z12.
**Limite de couverture : les contours français sont le jeu vectoriel EMODnet 2022
fortement généralisé à 1:500000, pas des ENC Shom. Aucune sonde ni roche qualifiée
française n'est annoncée. NOAA fournit les cinq familles aux USA.**

Les preuves locales sont dans `test-results/hydrography-2026-10-17/` (ignoré par
Git). Le [contrat d'architecture](../architecture/hydrography.md) donne les schémas,
endpoints primaires, conversions, algorithmes et limites exactes.

## A. Git initial

`feature/marine-bathymetry`, HEAD `20437348`,
`feat(map): add fixed aids lighthouses and marine lights`. Arbre propre.
Commandes exécutées avant modification : `git status --short`,
`git branch --show-current`, `git log --oneline -5`.

## B. Environnement

Backend 8004 déjà sain, `/health` et `/openapi.json` vérifiés. Instance réutilisée
pendant l'analyse, puis rechargée uniquement pour charger les nouveaux endpoints
et les corrections finales. Pas de changement de port ni de déploiement distant.
LGN LX1 USB `AV5PJV6328H03108`, Android 15/API35/arm64. Reverse déjà présent
`tcp:8004 → tcp:8004`, conservé sans le recréer. Aucun émulateur/desktop de validation.

## C. Sources

| Provider | Couches réelles | Trouvé / licence / limite |
|---|---|---|
| Shom WFS INSPIRE | `EPAVES_BDD_WFS:wrecks`, `obstrn` | Épaves et obstructions réelles autour des quatre zones françaises; objets 2D, CC BY-SA 4.0. BBOX explicitement EPSG:4326, sinon CRS natif 3857. Pas de promotion d'obstruction en rocher. |
| NOAA ENC Direct | 39 couches objets + 3 datum vérifiées dans 5 échelles; harbour 104/76/34/36/33/99/156/158/224 | Courbes, sondes, rochers, épaves, obstructions ponctuelles/linéaires/surfaciques réellement interrogés à Miami et alentours. CC0. Les objets absents d'une tuile ne prouvent pas une zone sans danger. |
| EMODnet WFS | `emodnet:contours`, `elevation` | Contours vectoriels publiés dérivés du DTM, version 2022; produit UE CC BY 4.0. Généralisation, suppression de contours fermés, résolution et datum limitent leur usage. Aucune reconstruction depuis le PNG. |

[Shom : licence et citation DOI](https://diffusion.shom.fr/donnees/epaves.html),
[NOAA ENC Direct](https://nauticalcharts.noaa.gov/data/gis-data-and-services.html),
[fiche exacte EMODnet](https://sextant.ifremer.fr/geonetwork/srv/api/records/4f7ab468-f4b9-4c2c-8d3b-49a375cf9964).
Les schémas WFS et métadonnées REST ont été lus; les fixtures réelles sont distinctes
des cas synthétiques et ne sont jamais injectées dans les tuiles runtime.

## D. Modèle

Trois modèles distincts : `DepthContour`, `Sounding`, `UnderwaterHazard`.
Valeur/unité originale + valeur en mètres, source/provenance, attributs bruts,
datum et référence, qualité et précision, géométrie d'origine, licence/dérivation.
Conversions m/ft/fathom explicites et testées. Signe conservé; HEIGHT reste distinct.
MultiPoint de sondes éclaté sans perdre la paire coordonnée/profondeur ni l'index.
Dangers : les six types géométriques demandés sont conservés et testés.
Shom : référence générique chart_datum publiée, définition locale inconnue.
NOAA : VERDAT ou zone compatible de même cellule/échelle, sinon inconnu.
EMODnet contours : datum exact de la couche non publié, conservé inconnu.

## E. Courbes

France : profondeurs réellement rencontrées 50/100/200/500m dans les tuiles
échantillonnées; pas de faux détails 2/5/10m. NOAA : notamment 0/1.8/3.6/5.4/9.1/
10.9/18.2m dans les tuiles mesurées. Major = zéro ou multiples de 10m publiés;
minor = autres. Sélection Z12 >=3m + major, Z13 >=1m + major, Z14 tout.

Captures finales ouvertes `fr-z11.9.png` (aucune courbe) et `fr-z12.0.png` (lignes
nettement visibles), même centre 5.93/43.06. Zoom relu depuis le SDK : 11.9 puis
12.0. Style actif sauvegardé : les deux couches `minzoom=12`, sources à 8004.
Sondes absentes à ces zooms. Z13, Z14, Z16 et Z17 contrôlés séparément.

## F. Sondes

NOAA SOUNDG, XYZ/Z en mètres; petites valeurs numériques sans pastille.
Grilles déterministes 64px à Z14/15/16, minimum de profondeur par cellule puis
précision/ID; références incompatibles séparées. Propriété minzoom de source et
couche =14. Exemple tuile Miami Z16 : 16 sondes, 5108 octets; Cape Florida Z16 :
2 sondes, 987 octets. La surface d'une tuile change avec le zoom : ces comptes
ne sont pas un benchmark de densité à emprise égale. Imbrication et maintien des
sondes peu profondes vérifiés sur une même emprise dans les tests.
Pas de sondes françaises disponibles dans le pipeline retenu.

## G. Dangers

Recherche réelle dans une BBOX Miami/Cape Florida : NOAA harbour 16 rochers,
64 épaves ponctuelles, 340 obstructions ponctuelles, 7 linéaires, 44 surfaciques,
4 épaves surfaciques (comptes de la requête, pas du seul écran).
Rocher `897296`, -80.1253611/25.7075, VALSOU=3.3m, WATLEV=3 : chaîne source →
normalisation → MVT → symbole Android contrôlée. Épave `80289` : VALSOU=0.6m,
catégorie publiée `dangerous wreck`, sans classification NoWave par seuil.
Shom Marseille `obstrn.2036` : brassiage 15.8m, symbole à sa position source.
Les datums absents restent inconnus; rocher/épave/obstruction ne fusionnent pas.
Le point exact Cape Florida échantillonné ne contient aucun danger dans sa tuile
centrale : les vues voisines contiennent des obstructions réelles.

## H. MVT

Trois routes `depth-contours`, `soundings`, `underwater-hazards`, source-layers
`depth_contour`, `sounding`, `underwater_hazard`. Extent4096, buffer64, Mercator.
Courbes simplifiées à une unité MVT; dangers/sondes non simplifiés. Clipping sans
centroïde ni contact de dimension inférieure. Courbes/dangers natifs Z14,
sondes Z16; overzoom au-delà. Requêtes partagées aux parents Z12/Z14 et cache
SQLite HTTP + cache mémoire MVT existants bornés. Sous seuil : vide valide sans
provider, testé. Panne complète sélectionnée :503, pas de cache vide trompeur.

## I. Performance

Mesure finale reproductible : 42 tuiles centrales, leur voisine et répétition,
`tiles/measurements.json`. Cache HTTP alimenté : 0 appel réseau central, 170 hits
HTTP centraux, 0 échec; voisinage également sans appel réseau. Maximum central
67696 octets, 187 features (courbes Miami Z12), génération maximale91.98ms;
répétition en mémoire <=0.006ms sur cette machine. Certaines tuiles répétées entre
zones étaient déjà dans le cache MVT; les mesures le montrent.

Premiers relevés avant alimentation de toutes les entrées : tuile contour Toulon
0.763s, Miami1.486s, dangers Miami0.669s; ils ne constituent pas un benchmark à
cache HTTP entièrement vide. Les requêtes mal paramétrées initiales sont exclues
du relevé final et leurs corrections sont décrites dans la revue.
Sur téléphone : changements de zone/zoom, pan, chargement et reload observés;
pas de freeze majeur observé. Aucun chiffre FPS annoncé. Des captures écran éteint
ou invalides ont été écartées et refaites, jamais retenues comme preuve.

## J. France

| Zone | Vérification réelle |
|---|---|
| Toulon | Courbe50m Z12, épaves/obstructions Shom; aides et reports présents. |
| Saint-Mandrier | Comparaison11.9/12.0, courbes50/100/200/500m au large; Z13; boucle publiée50m Z16; port Z17. |
| Giens | Courbe50m Z14, obstruction; pas de sondes françaises ajoutées. |
| Marseille | Courbe50m dans la tuile large Z12; obstruction réelle15.8m ciblée à Z16. |

Bords/continuité : rendu des courbes adjacentes sans cassure visible aux vues
contrôlées; tests clipping/simplification et relevé des tuiles voisines conservés.
Cela ne certifie pas une continuité hydrographique entre cartes ou sources.

## K. USA

Miami : Z12 avec contours peu profonds publiés, aides IALA B, dangers; vue locale
Z16 avec sondes. Cape Florida : vue localeZ14, phare, contours et sondes; pas de
danger inventé au centre. Rocher réel à Z16, symbolique submerged; les autres
états sont vérifiés par tests et restent conditionnés à un attribut publié.

## L. Android

APK `mobile/build/app/outputs/flutter-apk/app-debug.apk`, construite avec
`.env.json` local sans en exposer les secrets, `MARINE_API_BASE_URL=http://127.0.0.1:8004/`
et `BATHYMETRY_TILES_URL=http://127.0.0.1:8004/api/v1/map/bathymetry/{z}/{x}/{y}.png`.
Installation `adb install -r`, lancement à froid, compte/session conservés.
Pas de code de déplacement de caméra ajouté au produit : contrôle via service VM
du build debug et ADB. Coordonnées et zooms relus au SDK; captures via screencap.
Les requêtes réelles de l'app vers les trois routes nouvelles sont dans
`backend-mobile-requests.log`; configuration native dans `style-after-reload.json`.

Treize captures finales ont été réellement ouvertes : sept France, quatre USA et
deux GPS. Le manifest `screenshots.json` les liste avec leur empreinte.
Le contrôle GPS relit Z15.5, `following=false`, `IdleViewportState`; après un vrai
geste ADB, le centre reste déplacé durant le contrôle suivant (`gps-check.json`).
Non-régression : styles/tailles des bouées ×2, neutral noir, règles IALA A/B,
fixed aids/phares/feux, ports, raster/texture, halo jaune des reports, coordonnées,
badge Z et logique GPS existante conservés. Sources correspondantes inchangées,
suite Flutter complète passée; vues FR/USA et GPS vérifiées sur appareil.
Le halo de précision GPS existant est bleu : aucune recoloration n'est introduite.

## M. Tests

- `ruff check backend` : OK.
- `.venv/bin/python -m pytest -q` : **737 passed**, un avertissement existant
  FastAPI/Starlette/httpx. Inclut43 tests hydrographiques et toute la suite API/unit.
- `dart format --output=none --set-exit-if-changed lib test` :166 fichiers, aucun changement.
- `flutter analyze --no-pub` : aucune anomalie.
- `flutter test --no-pub` : **480 passed**.
- `flutter build apk --debug --no-pub` avec les defines locaux ci-dessus : OK.
  Avertissement existant de migration Kotlin des plugins; APK construite.
- `git diff --check` : OK.

Le premier lancement de pytest par l'exécutable nu ne trouvait pas le package
`backend`; la commande module ci-dessus inclut correctement la racine et exécute
la suite complète, sans désactiver de tests.

## N. Revue1

Diff intégral relu, nouveaux modules/contrats/catalogue inspectés.
Corrections : parseur signé distinct du parseur ancien de portée lumineuse;
conflits de catégories lors du merge; CRS explicite BBOX Shom; OID NOAA variable
(pagination sur l'OID natif); sélection de contours NOAA peu profonds dès Z12;
rocher inconnu distinct d'immergé et dry distinct de drying. Les valeurs Z Point
publiées évitent le bruit flottant XYZ. Tests et APK relancés après corrections.
Les modifications de formatage extérieures au périmètre ont été annulées.

## O. Revue2

Mission relue comme une nouvelle validation : références de datum documentées,
zone NOAA jointe seulement par cellule/échelle et couverture complète, exclusion
CATCOV=no coverage, géométries MultiPolygon et MultiPoint testées, contrat provider
étendu au socle commun sans import circulaire, licence attachée aux objets.
Aucune profondeur, qualité ou catégorie hydrographique synthétique en runtime.
Limites françaises conservées explicitement. Seuil et captures refaits sur APK
finale; style rechargé et sources/couches uniques contrôlés après reload.
Rendu et commandes GPS/reports restent disponibles, vue libre après recentrage.
Les tests complets ont été relancés après les corrections de code.

## P. Git final

Branche et HEAD inchangés. Détails exacts dans `git-status.txt`, `git-diff-stat.txt`
et `git-diff-check.txt` des preuves locales. `git diff --stat` ne compte pas les
fichiers nouveaux non suivis; ils figurent dans le status et le manifest.
**AUCUN COMMIT — AUCUN PUSH — AUCUNE PR.** Aucun reset/restore/clean/rebase/amend.
