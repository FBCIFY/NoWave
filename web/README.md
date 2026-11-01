# Web

Site Vite et assets partagés avec l’administration.

## Prérequis

- Node.js 24.
- Stack Docker du [projet](../README.md#lancer) déjà lancée.

## Lancer

Depuis `web/` :

```sh
npm ci
npm run dev -- --port 5173
```

Ouvrir `http://127.0.0.1:5173/`. Vite transmet les appels au backend sur
`http://127.0.0.1:8000` ; `NOWAVE_API_URL` permet de changer cette adresse.
La carte web utilise `MAPBOX_PUBLIC_TOKEN`, configuré dans le `.env` de la racine.
Le fond GEBCO et l’admin HTTPS sont servis par Docker sur `https://localhost:8443`.
Pour compiler les assets, lancer `npm run build` depuis `web/`.

## Tests

Depuis `web/`, après `npm ci` :

```sh
npm test
```
