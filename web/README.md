# NoWave web

Site Vite et assets partagés avec l’admin.

Prérequis : Node.js 24. Pour utiliser la base et les services réels, suivre
le [démarrage Docker du projet](../README.md#lancer-le-projet).

## Aperçu local sans base

Python 3.12. Depuis la racine, dans un premier terminal :

```sh
python3.12 -m venv .venv
. .venv/bin/activate
python -m pip install -r backend/requirements.txt
PYTHONPATH=backend python backend/tests/browser/preview.py --port 8000
```

Dans un second terminal :

```sh
cd web
npm ci
npm run dev -- --port 5173
```

Ouvrir [localhost:5173](http://127.0.0.1:5173/).
Le faux compte admin `admin@nowave.test` / `preview-only` sert à cet aperçu :
données en mémoire et modération désactivée.
Sur macOS, `Tester la refonte.command` lance les deux services après installation
des dépendances Python.

- `NOWAVE_API_URL` : backend du proxy Vite, `http://127.0.0.1:8000` par défaut.
- `MAPBOX_PUBLIC_TOKEN` : jeton public `pk.*` autorisé pour localhost.
- `NOWAVE_MAPBOX_CONFIG` : alternative au jeton direct, chemin du JSON contenant `MAPBOX_ACCESS_TOKEN`.

## Build

Depuis `web/` : `npm ci`, puis `npm run build`. Servir les assets du même build
que les pages admin.
