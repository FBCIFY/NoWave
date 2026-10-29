import json

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.config.production import configure_production
from app.config.settings import ConfigurationError


def test_production_requires_firebase_credentials(monkeypatch):
    monkeypatch.setenv("NOWAVE_ENV", "production")
    monkeypatch.setenv("DATABASE_URL", "postgresql://example/test")
    monkeypatch.setenv("PHOTO_STORAGE_BUCKET", "photos.test")
    monkeypatch.setenv("SCW_ACCESS_KEY", "test-key")
    monkeypatch.setenv("SCW_SECRET_KEY", "test-secret")
    monkeypatch.delenv("GOOGLE_APPLICATION_CREDENTIALS", raising=False)
    with pytest.raises(ConfigurationError, match="Firebase service account"):
        configure_production(FastAPI())


def test_production_host_and_origin_boundaries(monkeypatch, tmp_path):
    monkeypatch.setenv("NOWAVE_ENV", "production")
    monkeypatch.setenv("DATABASE_URL", "postgresql://example/test")
    monkeypatch.setenv("PHOTO_STORAGE_BUCKET", "photos.test")
    monkeypatch.setenv("SCW_ACCESS_KEY", "test-key")
    monkeypatch.setenv("SCW_SECRET_KEY", "test-secret")
    monkeypatch.setenv("GOOGLE_CLOUD_PROJECT", "unit-test-project")
    secret = tmp_path / "firebase.json"
    secret.write_text(
        json.dumps(
            {
                "type": "service_account",
                "project_id": "unit-test-project",
                "private_key": "test-only",
            }
        )
    )
    monkeypatch.setenv("GOOGLE_APPLICATION_CREDENTIALS", str(secret))
    app = FastAPI()
    configure_production(app)

    @app.get("/health")
    def health():
        return {"status": "ok"}

    client = TestClient(app, base_url="https://no-wave.fr")
    assert client.get("/health").status_code == 200
    assert (
        client.get("/health", headers={"Origin": "https://no-wave.fr"}).status_code
        == 200
    )
    assert (
        client.get(
            "/health", headers={"Origin": "https://attacker.example"}
        ).status_code
        == 403
    )
    assert (
        client.get("/health", headers={"Host": "attacker.example"}).status_code == 400
    )
