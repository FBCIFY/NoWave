from firebase_admin import auth

from app.application.ports.auth_provider import AuthProvider
from app.infrastructure.adapters.firebase_app import initialize_firebase


class FirebaseAuthAdapter(AuthProvider):
    def __init__(self):
        initialize_firebase()

    def verify_token(self, token: str, *, check_revoked: bool = False) -> dict:
        return auth.verify_id_token(token, check_revoked=check_revoked)

    def delete_identity(self, firebase_uid: str) -> None:
        try:
            auth.delete_user(firebase_uid)
        except auth.UserNotFoundError:
            # Une tentative précédente peut avoir déjà
            # supprimé l'identité Firebase.
            return
