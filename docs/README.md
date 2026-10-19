# Documentation NoWave

Cette page est l'index de référence des guides conservés dans le dépôt. Elle complète la [documentation technique du MVP](https://docs.google.com/document/d/1PbbCySYhRy8_aeU4T19nfPSq3dXU-QI9/edit), les migrations PostgreSQL et les décisions Linear. **Code de référence audité :** `dev` à [`6b54aa8`](https://github.com/FBCIFY/NoWave/commit/6b54aa861e5cda93bf9b573c443f5946d230945d), 19/10/2026.

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
| Administration | [administration.md](parcours/administration.md) | Modération et audit |
| Livraison | [deploiement.md](parcours/deploiement.md) | CI, `dev`, VPS et `main` |

## Preuves disponibles

- [Consignes et preuves de test](TESTING.md)
- [Rapport NW-128](test-reports/NW-128.md) — consulter son périmètre exact et ses limites.
- [Rapport NW-163](test-reports/NW-163.md) — résultats automatisés consignés, essais réels FCM/Mapbox restant à réaliser selon le rapport.

**Règle de traçabilité :** distinguer code présent, test automatisé présent, test exécuté avec résultat, validation Android/iOS réelle et vérification de la version déployée. Une référence de fichier ne prouve pas, à elle seule, une validation.

## Documents historiques

[BlueWay — Database Design — MVP](https://docs.google.com/document/d/1Gl4LLNGHcCR5BLrGtgfok0VrHJndEFfrR-ZWrPtdtSU/edit) est **ARCHIVÉ** (CON-027). Il sert exclusivement à retracer l'évolution de l'architecture ; il ne définit pas le contrat SQL ou métier actuel. La documentation technique courante et les migrations font référence.

## Décisions documentaires du 19/10/2026

- **CON-024 / A :** maintenir le cache HTTP MVT de 15 secondes et expliciter le décalage visuel potentiel.
- **CON-025 / C :** ne décrire comme disponibles que les routes réellement implémentées.
- **CON-026 / A :** documenter le déploiement existant depuis `dev`, sans inventer d'environnement distinct.
- **CON-027 / A :** conserver la conception BDD BlueWay comme archive historique.
- **CON-039 / C :** centraliser la documentation et la matrice de traçabilité, sans prétendre que les recettes manquantes sont validées.