from concurrent.futures import ThreadPoolExecutor
from threading import Barrier, Lock
from time import sleep
from types import SimpleNamespace

import firebase_admin
import pytest

from app.infrastructure.adapters.firebase_auth_adapter import FirebaseAuthAdapter
from app.infrastructure.adapters.firebase_push_sender import FirebasePushSender
from app.infrastructure.adapters.firebase_web_auth_adapter import initialize_firebase


def test_mobile_web_and_worker_share_one_initialization(monkeypatch):
    start = Barrier(12)
    registry_lock = Lock()
    app = None
    attempts = []
    expected = SimpleNamespace(
        project_id="test", credential=SimpleNamespace(get_credential=lambda: object())
    )

    def get_app():
        with registry_lock:
            if app is None:
                raise ValueError("not initialized")
            return app

    def initialize_app():
        nonlocal app
        attempts.append(1)
        sleep(0.02)  # Let concurrent callers reach the uninitialized registry.
        with registry_lock:
            if app is not None:
                raise ValueError("already initialized")
            app = expected
            return app

    monkeypatch.setattr(firebase_admin, "get_app", get_app)
    monkeypatch.setattr(firebase_admin, "initialize_app", initialize_app)
    monkeypatch.setattr(FirebasePushSender, "__init__", lambda self, *args: None)

    def create(index):
        start.wait(timeout=5)
        return (
            FirebaseAuthAdapter,
            initialize_firebase,
            FirebasePushSender.from_environment,
        )[index % 3]()

    with ThreadPoolExecutor(max_workers=12) as pool:
        list(pool.map(create, range(12)))
    assert len(attempts) == 1
    assert get_app() is expected


def test_initialization_failure_can_be_retried(monkeypatch):
    app = None
    attempts = []

    def get_app():
        if app is None:
            raise ValueError("not initialized")
        return app

    def initialize_app():
        nonlocal app
        attempts.append(1)
        if len(attempts) == 1:
            raise OSError("credentials unavailable")
        app = object()
        return app

    monkeypatch.setattr(firebase_admin, "get_app", get_app)
    monkeypatch.setattr(firebase_admin, "initialize_app", initialize_app)
    with pytest.raises(OSError):
        FirebaseAuthAdapter()
    initialize_firebase()
    FirebaseAuthAdapter()
    assert len(attempts) == 2


def test_existing_app_is_reused(monkeypatch):
    monkeypatch.setattr(firebase_admin, "get_app", lambda: object())
    monkeypatch.setattr(
        firebase_admin, "initialize_app", lambda: pytest.fail("already initialized")
    )
    FirebaseAuthAdapter()
    initialize_firebase()
