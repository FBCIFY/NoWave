# Administration web

`/admin` exige un e-mail Firebase vérifié et un profil actif de rôle `admin`.
Configurer `FIREBASE_WEB_API_KEY`, ou sa variante `_FILE`, pour la connexion.
La carte utilise `MAPBOX_PUBLIC_TOKEN`, jeton public `pk.*` limité aux domaines autorisés : transmis par Compose local, à injecter en production.

FastAPI sert `/admin-static/`. Nginx doit aussi servir le build web partagé sous `/assets/` et les tuiles GEBCO.
Sans jeton Mapbox, les listes et formulaires restent accessibles.

La session dure huit heures : cookie `__Host-nowave_admin_session`, `Secure`, `HttpOnly`, `SameSite=Strict`.
Chaque page revérifie la session et le profil. Les formulaires POST exigent un token CSRF ; la modération exige un motif.
La déconnexion ferme la session du navigateur et conserve la session mobile.
