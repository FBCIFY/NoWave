from types import SimpleNamespace
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from app.dependencies.admin_web_session import get_admin_web_session
from app.domain.errors import InvalidSessionError
from app.domain.user import User, UserRole
from app.main import app
from app.web.csrf import CSRF_COOKIE, session_csrf_token
from app.web.errors import SESSION_COOKIE
from app.web.routes.admin_pages import (
    get_admin_read_service,
    get_moderation_service,
)


ADMIN = User(
    firebase_uid="firebase-admin-nw127",
    username="admin-nw127",
    email="admin-nw127@nowave.test",
    role=UserRole.ADMIN,
)

REPORT_ID = UUID("11111111-1111-1111-1111-111111111111")
USER_ID = UUID("22222222-2222-2222-2222-222222222222")
ACTION_ID = UUID("33333333-3333-3333-3333-333333333333")


def enum_value(value):
    return SimpleNamespace(value=value)


class FakeAdminWebSession:
    def sign_in(self, email, password):
        return "session-cookie"

    def authenticate(self, session_cookie):
        if session_cookie != "session-cookie":
            raise InvalidSessionError("invalid session")
        return ADMIN


class FakeAdminReadService:
    def __init__(self):
        self.calls = []

    def list_reports(self, page=1, limit=20, status=None, now=None):
        self.calls.append(("list_reports", page, limit))
        return SimpleNamespace(
            items=[
                SimpleNamespace(
                    id=REPORT_ID,
                    category=enum_value("objet"),
                    status=enum_value("active"),
                    observed_at="2026-10-13 10:00",
                    version=4,
                )
            ],
            page=page,
            limit=limit,
            pages=3,
            total=41,
        )

    def get_report(self, report_id, now=None):
        self.calls.append(("get_report", report_id))
        return SimpleNamespace(
            id=report_id,
            category=enum_value("objet"),
            status=enum_value("active"),
            version=4,
            description="Bouée dérivante",
            positioning_mode=enum_value("gps"),
            observed_at="2026-10-13 10:00",
            expires_at="2026-10-14 10:00",
            longitude=5.9,
            latitude=43.1,
            removed_at=None,
            photo_status=enum_value("uploaded"),
            photo_hidden_at=None,
            author_username="navigateur",
            author_email="navigateur@nowave.test",
            author_status=enum_value("active"),
            boat_name="NoWave Test",
            boat_type=enum_value("voilier"),
        )

    def list_users(self, page=1, limit=20, status=None):
        self.calls.append(("list_users", page, limit))
        return SimpleNamespace(
            items=[
                SimpleNamespace(
                    id=USER_ID,
                    username="navigateur",
                    email="navigateur@nowave.test",
                    role=enum_value("user"),
                    status=enum_value("active"),
                )
            ],
            page=page,
            limit=limit,
            pages=1,
            total=1,
        )

    def list_moderation_actions(self, page=1, limit=20):
        self.calls.append(("list_moderation_actions", page, limit))
        return SimpleNamespace(
            items=[
                SimpleNamespace(
                    id=ACTION_ID,
                    created_at="2026-10-13 11:00",
                    admin_user_id=ADMIN.id,
                    action=enum_value("remove_report"),
                    target_report_id=REPORT_ID,
                    target_user_id=None,
                    target_photo_report_id=None,
                    reason="Signalement invalide",
                    previous_status="active",
                    new_status="removed",
                )
            ],
            page=page,
            limit=limit,
            pages=1,
            total=1,
        )


class FakeModerationService:
    def __init__(self):
        self.calls = []

    def _record(self, action, **kwargs):
        self.calls.append((action, kwargs))

    def remove_report(self, **kwargs):
        self._record("remove_report", **kwargs)

    def restore_report(self, **kwargs):
        self._record("restore_report", **kwargs)

    def hide_photo(self, **kwargs):
        self._record("hide_photo", **kwargs)

    def suspend_user(self, **kwargs):
        self._record("suspend_user", **kwargs)

    def reactivate_user(self, **kwargs):
        self._record("reactivate_user", **kwargs)


@pytest.fixture
def services():
    session = FakeAdminWebSession()
    reads = FakeAdminReadService()
    moderation = FakeModerationService()

    app.dependency_overrides[get_admin_web_session] = lambda: session
    app.dependency_overrides[get_admin_read_service] = lambda: reads
    app.dependency_overrides[get_moderation_service] = lambda: moderation

    yield reads, moderation

    app.dependency_overrides.clear()


@pytest.fixture
def client():
    return TestClient(app, base_url="https://testserver")


def sign_in(client):
    response = client.get("/admin/login")
    assert response.status_code == 200

    token = client.cookies.get(CSRF_COOKIE)

    response = client.post(
        "/admin/login",
        data={
            "email": "admin-nw127@nowave.test",
            "password": "secret",
            "csrf_token": token,
        },
        follow_redirects=False,
    )

    assert response.status_code == 303


def test_moderation_pages_require_admin_session(client, services):
    for path in (
        "/admin/reports",
        "/admin/users",
        "/admin/audit",
        f"/admin/reports/{REPORT_ID}",
    ):
        response = client.get(path, follow_redirects=False)

        assert response.status_code == 303
        assert response.headers["location"] == "/admin/login"


def test_reports_page_renders_paginated_results(client, services):
    reads, _ = services
    sign_in(client)

    response = client.get("/admin/reports?page=2&limit=20")

    assert response.status_code == 200
    assert "Signalements" in response.text
    assert str(REPORT_ID) in response.text
    assert "Page 2 sur 3" in response.text
    assert "41 résultat(s)" in response.text
    assert reads.calls == [("list_reports", 2, 20)]


def test_report_detail_renders_real_read_contract(client, services):
    reads, _ = services
    sign_in(client)

    response = client.get(f"/admin/reports/{REPORT_ID}")

    assert response.status_code == 200
    assert "Bouée dérivante" in response.text
    assert "5.9, 43.1" in response.text
    assert "NoWave Test" in response.text
    assert "Masquer la photo" in response.text
    assert reads.calls == [("get_report", REPORT_ID)]


def test_users_page_renders_accounts(client, services):
    reads, _ = services
    sign_in(client)

    response = client.get("/admin/users")

    assert response.status_code == 200
    assert "navigateur@nowave.test" in response.text
    assert "Suspendre" in response.text
    assert "Réactiver" in response.text
    assert reads.calls == [("list_users", 1, 20)]


def test_audit_page_is_read_only_history(client, services):
    reads, _ = services
    sign_in(client)

    response = client.get("/admin/audit")

    assert response.status_code == 200
    assert "Audit de modération" in response.text
    assert "Signalement invalide" in response.text
    assert "remove_report" in response.text
    assert reads.calls == [("list_moderation_actions", 1, 20)]


@pytest.mark.parametrize(
    ("collection", "target_id", "action_name", "label"),
    [
        ("reports", REPORT_ID, "remove", "Retirer le signalement"),
        ("reports", REPORT_ID, "restore", "Restaurer le signalement"),
        ("reports", REPORT_ID, "hide-photo", "Masquer la photo"),
        ("users", USER_ID, "suspend", "Suspendre l’utilisateur"),
        ("users", USER_ID, "reactivate", "Réactiver l’utilisateur"),
    ],
)
def test_five_action_forms_render(
    client,
    services,
    collection,
    target_id,
    action_name,
    label,
):
    sign_in(client)

    response = client.get(
        f"/admin/actions/{collection}/{target_id}/{action_name}"
    )

    assert response.status_code == 200
    assert label in response.text
    assert 'name="reason"' in response.text
    assert 'name="confirmed"' in response.text

    token = session_csrf_token("session-cookie")
    assert f'name="csrf_token" value="{token}"' in response.text


@pytest.mark.parametrize(
    ("collection", "target_id", "action_name", "service_method"),
    [
        ("reports", REPORT_ID, "remove", "remove_report"),
        ("reports", REPORT_ID, "restore", "restore_report"),
        ("reports", REPORT_ID, "hide-photo", "hide_photo"),
        ("users", USER_ID, "suspend", "suspend_user"),
        ("users", USER_ID, "reactivate", "reactivate_user"),
    ],
)
def test_five_actions_call_real_service_contract(
    client,
    services,
    collection,
    target_id,
    action_name,
    service_method,
):
    _, moderation = services
    sign_in(client)

    response = client.post(
        f"/admin/actions/{collection}/{target_id}/{action_name}",
        data={
            "csrf_token": session_csrf_token("session-cookie"),
            "reason": "Motif de test",
            "confirmed": "yes",
        },
    )

    assert response.status_code == 200
    assert "Action effectuée" in response.text

    assert len(moderation.calls) == 1
    called_method, kwargs = moderation.calls[0]

    assert called_method == service_method
    assert kwargs["admin"] is ADMIN
    assert kwargs["reason"] == "Motif de test"

    target_key = (
        "user_id"
        if collection == "users"
        else "report_id"
    )
    assert kwargs[target_key] == target_id


def test_action_requires_server_side_confirmation(client, services):
    _, moderation = services
    sign_in(client)

    response = client.post(
        f"/admin/actions/reports/{REPORT_ID}/remove",
        data={
            "csrf_token": session_csrf_token("session-cookie"),
            "reason": "Motif valide",
        },
    )

    assert response.status_code == 400
    assert "confirmer explicitement" in response.text
    assert moderation.calls == []


def test_action_rejects_forged_csrf_before_service_call(client, services):
    _, moderation = services
    sign_in(client)

    response = client.post(
        f"/admin/actions/reports/{REPORT_ID}/remove",
        data={
            "csrf_token": "forged-token",
            "reason": "Motif valide",
            "confirmed": "yes",
        },
    )

    assert response.status_code == 403
    assert "Formulaire expiré" in response.text
    assert moderation.calls == []
