# Documentation NoWave

Cet index distingue la [documentation technique Stage 4](https://docs.google.com/document/d/1Gez2BmfkdjTLyE9jkyf-U_QzJkUWQ9mu/edit), source fonctionnelle de référence, de son [PDF conservé dans le dépôt](NoWave_Documentation_Technique.pdf), des annexes spécialisées et des preuves. La version Stage 4 du 30/10/2026 décrit le code `dev` au commit [`ad54ffdb`](https://github.com/FBCIFY/NoWave/commit/ad54ffdb2cf359c36cf22b947494195bddcf87fb) (28/10/2026) ; elle ne prouve pas une recette ou un déploiement. La stricte identité du PDF du dépôt et du document du Drive n'a pas été établie.

## Démarrer et contribuer

- [Vue d'ensemble / installation](../README.md)
- [Application mobile Flutter](../mobile/README.md)
- [Site web autonome](../web/README.md)
- [Règles de contribution et revue](CONTRIBUTING.md)
- [Tests, CI et validation](TESTING.md)
- [Déploiement VPS](../deploy/README.md)
- [Correspondance fonctionnalités, code et tests](TESTING.md#correspondance-fonctionnelle-code-et-tests)

## Architecture marine : annexes techniques

Les documents suivants apportent des détails sur les fournisseurs, licences,
référentiels et algorithmes. Ils décrivent aussi des décisions historiques :
en cas de divergence, vérifier le code `dev` actuel et la documentation Stage 4.

- [Sources marines et normalisation](architecture/marine-sources.md) — choix, licences, fusion et provenances.
- [Hydrographie](architecture/hydrography.md) — courbes, sondes, datums et dangers.
- [Profondeurs EMODnet 2024](architecture/emodnet-depths.md) — contrat de grille, unités, erreurs et limites.
- [Chargement progressif et persistance NW-220](architecture/marine-zoom-persistence.md) — zoom, mosaïque, réponses partielles et caches.

## Parcours fonctionnels

Les parcours d'inscription, carte, signalements, alertes, administration et
déploiement sont décrits par la **documentation Stage 4** (contrats API, UML et
séquences). Les scénarios de vérification et chemins de code qui apportaient
une information complémentaire sont consolidés dans
[TESTING.md — Recette fonctionnelle par parcours](TESTING.md#recette-fonctionnelle-par-parcours-consolidation-documentaire-du-30102026).
Le déroulement d'une livraison et son retour arrière sont documentés dans
[deploy/README.md](../deploy/README.md). Les anciens guides `docs/parcours/`
ont été retirés après cette consolidation.

## Preuves disponibles

- [Consignes et preuves de test](TESTING.md)
- [Preuves et résultats des tests — 29/10/2026](NoWave_Preuves_et_resultats_des_tests_29-10-2026.pdf) — bilan Stage 4 et limites des vérifications.
- [Rapport de bug tracking](NoWave_Rapport_Bug_Tracking.pdf) — anomalies, corrections et vérifications.
- [Dossier Stage 4 dans Drive](https://drive.google.com/drive/folders/1Oaq6JQChxLm8siO_6OPlh5odmq5J-vKW) — livrables de référence.

**Règle de traçabilité :** distinguer code présent, test automatisé présent, test exécuté avec résultat, validation Android/iOS réelle et vérification de la version déployée. Une référence de fichier ne prouve pas, à elle seule, une validation. Les anciens rapports individuels de `docs/test-reports/` restent dans l'historique Git, mais ne font plus partie de la documentation courante. Le bilan Stage 4 n'est pas une copie exhaustive des journaux et captures.

## Documents historiques

- [Ancien relevé DNS non vérifié](archives/no-wave-dns-historique.txt) : **archive uniquement** ; ne pas appliquer les enregistrements sans contrôle de la zone DNS active.

[BlueWay — Database Design — MVP](https://docs.google.com/document/d/1Gl4LLNGHcCR5BLrGtgfok0VrHJndEFfrR-ZWrPtdtSU/edit) est **ARCHIVÉ** ([FIX T16 (NW-169)](https://linear.app/blueway/issue/NW-169)). Il sert exclusivement à retracer l'évolution de l'architecture ; il ne définit pas le contrat SQL ou métier actuel. La documentation technique courante et les migrations font référence.

## Décisions documentaires du 19/10/2026

- [FIX T13 (NW-166)](https://linear.app/blueway/issue/NW-166): maintenir le cache HTTP MVT de 15 secondes et expliciter le décalage visuel potentiel.
- [FIX T14 (NW-167)](https://linear.app/blueway/issue/NW-167): ne décrire comme disponibles que les routes réellement implémentées.
- [FIX T15 (NW-168)](https://linear.app/blueway/issue/NW-168): documenter le déploiement existant depuis `dev`, sans inventer d'environnement distinct.
- [FIX T16 (NW-169)](https://linear.app/blueway/issue/NW-169): conserver la conception BDD BlueWay comme archive historique.
- [FIX T17 (NW-170)](https://linear.app/blueway/issue/NW-170): centraliser la documentation et les correspondances de traçabilité dans TESTING.md, sans prétendre que les recettes manquantes sont validées.