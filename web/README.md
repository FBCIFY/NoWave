# Site web

Le site tourne avec Vite et Node.js 24. Démarrer d’abord la [stack Docker](../README.md#lancer-en-local), puis ouvrir un terminal dans `web/` :

```sh
npm ci
npm run dev -- --port 5173
```

Le serveur de dev est sur `http://127.0.0.1:5173/`.
Son proxy vise l’API sur `http://127.0.0.1:8000` ; définir `NOWAVE_API_URL` pour utiliser un autre backend.

La carte lit le jeton `MAPBOX_PUBLIC_TOKEN` transmis à l’API par le `.env` de la racine.
Pour le fond GEBCO et l’admin en HTTPS, utiliser le site Docker sur `https://localhost:8443`.

Tests et compilation, dans le même dossier :

```sh
npm test
npm run build
```

Le site et l’admin doivent servir les assets du même build.
