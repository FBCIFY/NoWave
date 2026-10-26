# Documentation NoWave

Cette page est l'index de référence des guides conservés dans le dépôt. Elle complète la [documentation technique du MVP](https://docs.google.com/document/d/1PbbCySYhRy8_aeU4T19nfPSq3dXU-QI9/edit), les migrations PostgreSQL et les décisions Linear. **Code de référence vérifié pour cet index :** `dev` à [`c3172ad`](https://github.com/FBCIFY/NoWave/commit/c3172adf8c4dcace9d38d6cf44e459abad97ffbd) (23/10/2026) ; mise à jour documentaire le 26/10/2026. Les rapports historiques conservent leur SHA propre.

## Démarrer et contribuer

- [Vue d'ensemble / installation](../README.md)
- [Application mobile Flutter](../mobile/README.md)
- [Site web autonome](../web/README.md)
- [Règles de contribution et revue](CONTRIBUTING.md)
- [Tests, CI et validation](TESTING.md)
- [Déploiement VPS](../deploy/README.md)
- [Matrice de traçabilité](traceability-matrix.md)

## Parcours fonctionnels

| Parcours | Document | Périmètre |
| --- | --- | --- |
| Compte et profil | [authentification.md](parcours/authentification.md) | Firebase, profil, préférences, bateau |
| Carte | [cartographie.md](parcours/cartographie.md) | GPS, MVT, cache et détails |
| Signalements | [signalements.md](parcours/signalements.md) | Publication manuelle et photo, stockage |
| Notifications | [notifications.md](parcours/notifications.md) | Éligibilité, FCM, historique et navigation |
| Administration | [administration.md](parcours/administration.md) | Surveillance cartographique NW-244, utilisateurs, modération et audit |
| Livraison | [deploiement.md](parcours/deploiement.md) | CI, `dev`, VPS et `main` |

## Architecture marine et interface de surveillance

- [Persistance des couches marines et zooms](architecture/marine-zoom-persistence.md) : règles de chargement, apparition et conservation visuelle (NW-220).
- [Sources marines](architecture/marine-sources.md) : provenance, formats, limitations et endpoints cartographiques.
- [Centre de surveillance web](../backend/app/web/README.md) : Mapbox GL JS, GEBCO, 1 000 signalements au maximum par emprise, clusters et limites de recette.
- [Recette navigateur de l'administration](../backend/tests/browser/README.md) : tests Playwright simulés en CI, parcours Mapbox réels à exécuter avec configuration externe.

## Preuves disponibles

- [Consignes et preuves de test](TESTING.md)
- [Rapport NW-128](test-reports/NW-128.md) — consulter son périmètre exact et ses limites.
- [Rapport NW-163](test-reports/NW-163.md) — résultats automatisés consignés, essais réels FCM/Mapbox restant à réaliser selon le rapport.
- [Rapport NW-244 après fusion](test-reports/NW-244-post-merge.md) — correctifs de l'administration, preuves navigateur/PostGIS et limites des services externes.

**Règle de traçabilité :** distinguer code présent, test automatisé présent, test exécuté avec résultat, validation Android/iOS réelle et vérification de la version déployée. Une référence de fichier ne prouve pas, à elle seule, une validation.

## Documents historiques

[BlueWay — Database Design — MVP](https://docs.google.com/document/d/1Gl4LLNGHcCR5BLrGtgfok0VrHJndEFfrR-ZWrPtdtSU/edit) est **ARCHIVÉ** ([FIX T16 (NW-169)](https://linear.app/blueway/issue/NW-169)). Il sert exclusivement à retracer l'évolution de l'architecture ; il ne définit pas le contrat SQL ou métier actuel. La documentation technique courante et les migrations font référence.

## Décisions documentaires du 19/10/2026

- [FIX T13 (NW-166)](https://linear.app/blueway/issue/NW-166): maintenir le cache HTTP MVT de 15 secondes et expliciter le décalage visuel potentiel.
- [FIX T14 (NW-167)](https://linear.app/blueway/issue/NW-167): ne décrire comme disponibles que les routes réellement implémentées.
- [FIX T15 (NW-168)](https://linear.app/blueway/issue/NW-168): documenter le déploiement existant depuis `dev`, sans inventer d'environnement distinct.
- [FIX T16 (NW-169)](https://linear.app/blueway/issue/NW-169): conserver la conception BDD BlueWay comme archive historique.
- [FIX T17 (NW-170)](https://linear.app/blueway/issue/NW-170): centraliser la documentation et la matrice de traçabilité, sans prétendre que les recettes manquantes sont validées.