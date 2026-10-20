# Parcours — Inscription, profil et consentements

**Référence :** `dev@6b54aa8` (19/10/2026). Références : NW-51, NW-52, NW-117, NW-153, NW-155. [Documentation technique](https://docs.google.com/document/d/1PbbCySYhRy8_aeU4T19nfPSq3dXU-QI9/edit).

## Objectif et étapes

1. L'utilisateur crée une identité Firebase par e-mail et mot de passe puis valide son adresse. Il peut demander un lien de réinitialisation.
2. Le mobile lit le profil avec `GET /api/v1/users/me`. La création initiale, déclenchée explicitement et séparément, utilise `POST /api/v1/users/me` avec un pseudonyme.
3. L'utilisateur configure son profil, ses informations de bateau optionnelles et ses préférences de consentement. `PATCH /api/v1/users/me` met à jour les préférences concernées.
4. L'enregistrement de l'installation utilise `PUT /api/v1/devices/current`; la désactivation utilise `DELETE /api/v1/devices/current`. Une identité Firebase vérifiée et le contrôle serveur conditionnent l'accès aux routes métier.

## Implémentation

- Flutter : `mobile/lib/features/auth/`, `mobile/lib/features/profile/`, `mobile/lib/core/`.
- FastAPI : `backend/app/api/routes/users.py`, `boats.py`, `devices.py` ; `backend/app/api/dependencies/auth.py`.
- API : `POST/GET/PATCH/DELETE /users/me`, `GET/POST/PATCH/DELETE /users/me/boat`, opérations d'appareil sous `/devices/current`.

## Cas particuliers

Une réponse perdue après création de profil peut entraîner une relecture du profil existant. Ne pas confondre les erreurs de pseudonyme déjà pris, de compte déjà créé et d'e-mail déjà lié à un autre utilisateur. Les permissions OS des notifications sont distinctes du consentement NoWave ; les choix peuvent être modifiés depuis le profil.

## Preuves et limites

Tests sources disponibles : `backend/tests/api/test_users.py`, `backend/tests/api/test_boats.py` et `mobile/test/features/profile/`. Leur présence n'atteste pas d'une exécution réussie dans ce correctif. Les essais sur appareils et la disponibilité Firebase réelle doivent être suivis séparément dans la [matrice](../traceability-matrix.md).