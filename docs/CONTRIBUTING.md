# Contribuer à NoWave

Les changements passent par une branche de travail, une PR vers `dev`, puis une revue par un autre membre de l’équipe. `main` contient les releases stables.

## Créer une branche

Depuis un dossier de travail propre :

```sh
git switch dev
git pull --ff-only origin dev
git switch -c docs/installation
```

Utilise un nom court qui décrit le travail. Préfixes usuels : `feat/`, `fix/`, `docs/`, `refactor/`, `test/`, `chore/`.

## Ouvrir une PR

1. Fais des commits ciblés et lance les [contrôles utiles](TESTING.md).
2. Pousse ta branche.
3. Ouvre une PR vers `dev` avec le problème, le changement et les résultats des tests.
4. Fais relire par un autre membre, puis résous les remarques bloquantes avant la fusion.

```sh
git add <fichiers-modifies>
git commit -m "docs: simplifier le guide d’installation"
git push -u origin docs/installation
```

Les secrets restent hors Git. La documentation décrit le comportement du code présent ; une fonction prévue doit être indiquée comme telle.

## Livrer

Un push sur `dev` lance la CI. Le déploiement VPS démarre après réussite des contrôles et audits. Pour une release stable, termine la recette puis ouvre une PR de `dev` vers `main`.

Les règles sont les mêmes pour toute l’équipe : aucun développement ni push direct sur `dev` ou `main`.
