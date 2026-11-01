# NoWave web

Site public et carte partagée avec l’administration. Versions des outils et
contrôles : [tests](../docs/TESTING.md). [Contrats API](../docs/API.md).

## Stack locale

Suivre le [démarrage du projet](../README.md#lancer-le-projet), puis ouvrir
[le site](https://localhost:8443) ou [l’admin](https://localhost:8443/admin).
`MAPBOX_PUBLIC_TOKEN` doit autoriser localhost.

## Aperçu sans base

Sur macOS, ouvrir `Tester la refonte.command`. Connexion de démo :
`admin@nowave.test` / `preview-only`. Données en mémoire, modération désactivée.
Lancement manuel depuis la racine, avec l’environnement Python du [guide de tests](../docs/TESTING.md#backend) activé, dans deux terminaux :

```sh
PYTHONPATH=backend python backend/tests/browser/preview.py --port 8000
```

```sh
cd web
npm ci
npm run dev -- --port 5173
```

Aperçu : [localhost:5173](http://127.0.0.1:5173/).
`NOWAVE_API_URL` change le backend Vite (défaut : port 8000).
La carte demande `MAPBOX_PUBLIC_TOKEN` ou `NOWAVE_MAPBOX_CONFIG`, chemin du JSON
contenant `MAPBOX_ACCESS_TOKEN`.

## Build

Depuis `web/` : `npm run build`. Servir les assets du même build que les pages
admin. Configuration de production : [déploiement](../deploy/README.md).
