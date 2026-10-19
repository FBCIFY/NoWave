# Parcours — Contrôles, VPS et release

**Référence :** `dev@6b54aa8` (19/10/2026). Correctif [FIX T15 (NW-168)](https://linear.app/blueway/issue/NW-168). Vérification documentaire attribuée à Jonathan ; référent opérationnel historique : Brice (NW-57 / NW-84).

## Processus observé

```text
Branche de travail → PR vers dev → revue et CI (validation seulement)
                                          ↓
                                  fusion dans dev
                                          ↓
                                   push sur dev
                                          ↓
                           CI : Python / Flutter / PostGIS / web
                                          ↓ si succès
                        production.yml (audits et construction)
                                          ↓ si succès et événement push dev
                              VPS Hostinger (SHA validé)

Release stable : QA finale → PR dev vers main → main (référence stable)
                                [pas de déploiement autonome depuis main]
```

Le workflow `.github/workflows/checks.yml` porte les événements de PR, de push `dev` et de lancement manuel. `.github/workflows/production.yml` est un workflow réutilisable appelé après les contrôles. Un échec bloque la livraison. Les PR et exécutions manuelles restent des validations sans mise en production. La configuration GitHub utilise un environnement nommé `production`, mais cela ne prouve **pas** l'existence d'un serveur « staging » séparé.

## Serveur et vérification

Les scripts `deploy/hostinger/ci-deploy.sh` et `deploy/hostinger/deploy.sh` vérifient les images, sauvegardent les données selon leurs responsabilités, appliquent les migrations et contrôlent la version avant exposition publique. Les secrets Firebase, Scaleway et SSH demeurent hors Git.

Comparer la révision délivrée avec `GET /version`, puis vérifier les parcours publics, l'état de la base et les workers selon [deploy/README.md](../../deploy/README.md). Les contrôles de conteneur ne prouvent pas à eux seuls les notifications effectivement reçues sur un téléphone.

## Références

- [Documentation de déploiement opérationnel](../../deploy/README.md)
- [Contrôles de tests et audits](../TESTING.md)
- [Conventions de branches](../CONTRIBUTING.md)
- [Matrice de traçabilité](../traceability-matrix.md)