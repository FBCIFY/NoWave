# Administration web

`/admin` regroupe la carte de surveillance, les utilisateurs, la modération et
l'audit. FastAPI rend les pages Jinja ; la carte partage son moteur avec le site
public. L'accès exige une session Firebase et un profil administrateur actif.

## Configuration

- `FIREBASE_WEB_API_KEY` active la connexion par e-mail et mot de passe.
- `MAPBOX_PUBLIC_TOKEN` fournit un jeton public `pk.*` limité aux domaines utilisés.
  L'injecter dans le processus API ; le Compose local le transmet, celui de
  production exige une configuration externe.
- FastAPI sert les ressources `/admin-static/`. Nginx ajoute le build partagé
  `/assets/` et les tuiles GEBCO ; utiliser la pile complète pour vérifier la carte.

Les lectures privées sous `/admin/data` vérifient la session et répondent
`Cache-Control: no-store`. Les actions de modération passent par des formulaires
avec motif, confirmation et CSRF. Chaque action réussie écrit une entrée d'audit.

## Carte et navigation

Le fil charge les observations actives par pages de 50 via
`/api/v1/map/observations`, avec recherche et filtre de catégorie. La pagination
par curseur conserve les filtres. Chaque observation chargée a son marqueur.
La sélection charge le détail privé via `/admin/data/reports/{uuid}`.

La carte démarre en globe orienté nord, adapte son zoom à l'écran et permet
d'atteindre Z12. GEBCO fournit le fond marin mondial Z0–Z6, qui s'efface entre
Z6 et Z8. Le raster doit être placé après la couche `water` de `dark-v11`.
Les terres utilisent les couches vectorielles `landcover` et `hillshade` de Mapbox.

Les trois catégories partagent les couleurs du mobile : animal marin `#06B6D4`,
obstacle `#F97316`, pollution `#7C3AED`. Un jeton absent laisse les listes et
formulaires accessibles et affiche un message d'indisponibilité sur la carte.

Le cadrage, les filtres et la pagination sont conservés dans l'onglet lors des
retours entre liste, fiche et action. Chaque nouvelle lecture annule la précédente
et vérifie la sélection courante avant affichage. Sur mobile, liste et fiche
s'affichent à tour de rôle.

L'historique `/admin/data/users/{uuid}/reports?page=1` renvoie `items`, `page`
et `has_more`, par pages de 20. L'ancienne lecture cartographique par emprise
`/admin/data/reports?west=...&south=...&east=...&north=...` reste limitée à
1 000 résultats et indique `truncated` si nécessaire.

## Vérifier en local

Le [guide web](../../../web/README.md) décrit la pile Docker HTTPS complète.
La [recette navigateur](../../tests/browser/README.md) fournit un aperçu en mémoire
et les tests Playwright sur une base PostGIS temporaire. Pour valider l'intégration
réelle, utiliser un compte, des données et des services de test isolés.
