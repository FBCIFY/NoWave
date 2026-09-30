import firebase_admin
from firebase_admin import auth

from app.infrastructure.adapters.firebase_auth_adapter import FirebaseAuthAdapter


def test_verify_token_calls_firebase(monkeypatch):
    monkeypatch.setattr(
        firebase_admin,
        "get_app",
        lambda: object(),
    )

    expected_identity = {
        "uid": "firebase-user-123",
        "email": "user@nowave.test",
        "email_verified": True,
    }

    monkeypatch.setattr(
        auth,
        "verify_id_token",
        lambda token: expected_identity,
    )

    adapter = FirebaseAuthAdapter()

    identity = adapter.verify_token("firebase-token-123")

    assert identity == expected_identity


def test_delete_identity_calls_firebase(monkeypatch):
    monkeypatch.setattr(
        firebase_admin,
        "get_app",
        lambda: object(),
    )

    deleted_uids = []

    monkeypatch.setattr(
        auth,
        "delete_user",
        lambda firebase_uid: deleted_uids.append(firebase_uid),
    )

    adapter = FirebaseAuthAdapter()

    adapter.delete_identity("firebase-user-123")

    assert deleted_uids == ["firebase-user-123"]
