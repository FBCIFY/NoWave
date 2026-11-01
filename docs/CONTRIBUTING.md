# Contribution Guidelines — NoWave

## Branch organization

The project uses two main branches:

- `main`: stable version of the project, used in particular for the MVP presentation.
- `dev`: integration branch containing validated features before they move to `main`.

Development must be done in working branches created from `dev`.

## Workflow

The project workflow is:

`feat/*` → `dev` → `main`

A feature must never be developed directly on `main` or `dev`.

## `main` branch

`main` represents the stable version of the project.

Rules:

- No direct development on `main`.
- No direct push to `main`.
- Changes reach `main` only through a Pull Request.
- A Pull Request to `main` should normally come from `dev`.
- `main` must remain in a working and presentable state.

## `dev` branch

`dev` is the shared integration branch.

Rules:

- No direct development on `dev`.
- No direct push to `dev`.
- Each feature or fix has its own branch.
- Changes are integrated into `dev` through a Pull Request.
- A Pull Request must be reviewed by at least one other team member before being merged.

## Working branches

Working branches are created from `dev`.

Naming convention:

- `feat/...`: new feature
- `fix/...`: bug fix
- `docs/...`: documentation
- `refactor/...`: code restructuring without functional change
- `test/...`: adding or modifying tests
- `chore/...`: maintenance, configuration or tooling

Examples:

`feat/maritime-map`

`feat/user-authentication`

`fix/map-loading`

`docs/api-documentation`

## Before starting a task

Update `dev`:

```bash
git switch dev
git pull origin dev
```

Then create a branch:

```bash
git switch -c chore/BLU-50/configurer-tests-controles-automatiques-pr
```

## Once the work is done

Create the commits, then push the branch to GitHub:

```bash
git add <fichiers-de-la-tache>
git commit -m "feat: feature description"
git push -u origin chore/BLU-50/configurer-tests-controles-automatiques-pr
```

Then open a Pull Request:

`feat/...` → `dev`

The Pull Request must be reviewed by at least one other team member before being merged.

## Promoting to a stable version

When the version in `dev` is considered stable:

`dev` → Pull Request → `main`

No `feat/*` branch may be merged directly into `main`.

## General rule

All three team members — Jonathan, Vadim and Brice — follow the same workflow.

Nobody develops directly on `main` or `dev`, including the repository owner.

## Contrôles automatiques

Consulter [TESTING.md](TESTING.md) pour reproduire les contrôles Python, Flutter,
PostGIS et web, les audits de production, retrouver les rapports et configurer
les contrôles obligatoires. Le workflow **NoWave CI** regroupe ces vérifications
et conditionne le déploiement automatique depuis `dev` à leur réussite.
