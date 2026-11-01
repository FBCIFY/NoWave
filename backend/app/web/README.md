# Administration web

`/admin` regroupe surveillance cartographique, utilisateurs, modération et audit.
La connexion exige un e-mail Firebase vérifié et un profil actif de rôle `admin`.

## Configuration

- `FIREBASE_WEB_API_KEY` ou sa variante `_FILE` active la connexion.
- `MAPBOX_PUBLIC_TOKEN` fournit le jeton public `pk.*`, limité aux domaines utilisés.
  Compose local le transmet ; la production demande une injection externe.
- FastAPI sert `/admin-static/`. Nginx ajoute `/assets/` et les tuiles GEBCO.
  Utiliser la pile complète du [guide web](../../../web/README.md) pour vérifier la carte.

La session dure huit heures : cookie `__Host-nowave_admin_session`, `Secure`,
`HttpOnly`, `SameSite=Strict`. Chaque page revérifie la session et le profil.
Les formulaires POST exigent un token CSRF et les actions de modération un motif.
La déconnexion ferme la session du navigateur en conservant la session mobile.

Le fil public et la sélection privée partagent le moteur cartographique du site.
Le cadrage, les filtres et la pagination restent dans l'onglet pendant la navigation.
Sans jeton Mapbox, listes et formulaires restent accessibles.

Les [contrats HTTP](../../../docs/API.md) détaillent l'API REST et les lectures
JSON de la session web. La [recette navigateur](../../tests/browser/README.md)
fournit l'aperçu local et les tests sur PostGIS isolé.
