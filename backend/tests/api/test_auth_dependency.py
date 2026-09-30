from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient

import app.api.dependencies.auth as auth_dependency


app = FastAPI()


@app.get("/protected")
def protected_route(
    identity: dict = Depends(auth_dependency.get_current_identity),
):
    return identity


client = TestClient(app)


def test_valid_token_returns_identity(monkeypatch):
    class FakeFirebaseAuthAdapter:
        def verify_token(self, token: str) -> dict:
            assert token == "valid-token"

            return {
                "uid": "firebase-user-123",
                "email": "user@nowave.test",
                "email_verified": True,
            }

    monkeypatch.setattr(
        auth_dependency,
        "FirebaseAuthAdapter",
        FakeFirebaseAuthAdapter,
    )

    response = client.get(
        "/protected",
        headers={
            "Authorization": "Bearer valid-token",
        },
    )

    assert response.status_code == 200
    assert response.json()["uid"] == "firebase-user-123"


def test_missing_token_returns_401():
    response = client.get("/protected")

    assert response.status_code == 401
    assert response.json()["detail"] == "Authentication required"


def test_invalid_token_returns_401(monkeypatch):
    class FakeFirebaseAuthAdapter:
        def verify_token(self, token: str) -> dict:
            raise ValueError("invalid token")

    monkeypatch.setattr(
        auth_dependency,
        "FirebaseAuthAdapter",
        FakeFirebaseAuthAdapter,
    )

    response = client.get(
        "/protected",
        headers={
            "Authorization": "Bearer invalid-token",
        },
    )

    assert response.status_code == 401
    assert response.json()["detail"] == "Invalid authentication token"
