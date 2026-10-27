from types import SimpleNamespace
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from app.dependencies.admin_web_session import get_admin_web_session
from app.domain.errors import (
    InvalidSessionError,
    PhotoNotFoundError,
    ReportNotFoundError,
)
from app.domain.pagination import MAX_PAGE
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
                    description="Bouée dérivante",
                    author_username="navigateur",
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
            photo_object_key="reports/photo.jpg",
            author_id=USER_ID,
            author_deleted=False,
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

    def list_moderation_actions(self, page=1, limit=20, report_id=None):
        self.calls.append(("list_moderation_actions", page, limit, report_id))
        return SimpleNamespace(
            items=[
                SimpleNamespace(
                    id=ACTION_ID,
                    created_at="2026-10-13 11:00",
                    admin_user_id=ADMIN.id,
                    admin_username=ADMIN.username,
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
        f"/admin/users/{USER_ID}/reports",
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
    assert "Bouée dérivante" in response.text
    assert "navigateur" in response.text
    assert "Page 2 sur 3" in response.text
    assert "41 résultat(s)" in response.text
    assert 'href="/#carte"' not in response.text
    assert 'aria-current="page"' in response.text
    assert reads.calls == [("list_reports", 2, 20)]


def test_report_detail_renders_real_read_contract(client, services):
    reads, _ = services
    sign_in(client)

    response = client.get(f"/admin/reports/{REPORT_ID}")

    assert response.status_code == 200
    assert "Bouée dérivante" in response.text
    assert "navigateur" in response.text
    assert "navigateur@nowave.test" not in response.text
    assert "Mode de positionnement" not in response.text
    assert "<dt>Version</dt>" not in response.text
    assert "Historique de modération" in response.text
    assert "Signalement invalide" in response.text
    assert ADMIN.username in response.text
    assert "Masquer la photo" in response.text
    assert reads.calls == [
        ("get_report", REPORT_ID),
        ("list_moderation_actions", 1, 20, REPORT_ID),
    ]


def test_report_history_paginates_only_the_selected_report(client, services):
    reads, _ = services
    sign_in(client)
    original_history = reads.list_moderation_actions

    def paginated_history(**kwargs):
        result = original_history(**kwargs)
        result.pages = 3
        result.total = 41
        return result

    reads.list_moderation_actions = paginated_history

    response = client.get(f"/admin/reports/{REPORT_ID}?history_page=2")

    assert response.status_code == 200
    assert 'id="report-history" open' in response.text
    assert '?history_page=1#report-history' in response.text
    assert '?history_page=3#report-history' in response.text
    assert reads.calls == [
        ("get_report", REPORT_ID),
        ("list_moderation_actions", 2, 20, REPORT_ID),
    ]


@pytest.mark.parametrize("page", [0, -1, MAX_PAGE + 1, "invalid"])
def test_report_history_rejects_invalid_page(client, services, page):
    reads, _ = services
    sign_in(client)

    response = client.get(f"/admin/reports/{REPORT_ID}?history_page={page}")

    assert response.status_code == 422
    assert reads.calls == []


def test_missing_report_does_not_load_history(client, services):
    reads, _ = services
    sign_in(client)

    def missing_report(**kwargs):
        raise ReportNotFoundError("not found")

    reads.get_report = missing_report

    response = client.get(f"/admin/reports/{REPORT_ID}")

    assert response.status_code == 404
    assert "Signalement introuvable" in response.text
    assert reads.calls == []


def test_report_without_moderation_history_is_explicit(client, services):
    reads, _ = services
    sign_in(client)
    reads.list_moderation_actions = lambda **kwargs: SimpleNamespace(
        items=[], page=1, limit=20, pages=0, total=0,
    )

    response = client.get(f"/admin/reports/{REPORT_ID}")

    assert response.status_code == 200
    assert "Aucune action de modération." in response.text
    assert "Signalement invalide" not in response.text


def test_users_page_renders_accounts(client, services):
    reads, _ = services
    sign_in(client)

    response = client.get("/admin/users")

    assert response.status_code == 200
    assert "navigateur@nowave.test" in response.text
    assert "Suspendre" in response.text
    assert "Réactiver" not in response.text
    assert reads.calls == [("list_users", 1, 20)]


def test_audit_page_is_read_only_history(client, services):
    reads, _ = services
    sign_in(client)

    response = client.get("/admin/audit")

    assert response.status_code == 200
    assert "Audit de modération" in response.text
    assert "Signalement invalide" in response.text
    assert "Signalement retiré" in response.text
    assert reads.calls == [("list_moderation_actions", 1, 20, None)]


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



@pytest.mark.parametrize("reason", ["", "   "])
def test_action_rejects_blank_reason_with_422(client, services, reason):
    _, moderation = services
    sign_in(client)

    response = client.post(
        f"/admin/actions/reports/{REPORT_ID}/remove",
        data={
            "csrf_token": session_csrf_token("session-cookie"),
            "reason": reason,
            "confirmed": "yes",
        },
    )

    assert response.status_code == 422
    assert "motif est obligatoire" in response.text.lower()
    assert moderation.calls == []


def test_hide_photo_not_found_returns_html_404(client, services):
    _, moderation = services
    sign_in(client)

    def missing_photo(**kwargs):
        raise PhotoNotFoundError("report has no photo")

    moderation.hide_photo = missing_photo

    response = client.post(
        f"/admin/actions/reports/{REPORT_ID}/hide-photo",
        data={
            "csrf_token": session_csrf_token("session-cookie"),
            "reason": "Photo non exploitable",
            "confirmed": "yes",
        },
    )

    assert response.status_code == 404
    assert response.headers["content-type"].startswith("text/html")
    assert "aucune photo à masquer" in response.text.lower()


def test_report_without_photo_does_not_offer_hide_action(client, services):
    reads, _ = services
    sign_in(client)

    original_get_report = reads.get_report

    def get_report_without_photo(report_id, now=None):
        item = original_get_report(report_id, now)
        item.photo_status = None
        item.photo_hidden_at = None
        return item

    reads.get_report = get_report_without_photo

    response = client.get(f"/admin/reports/{REPORT_ID}")

    assert response.status_code == 200
    assert "Masquer la photo" not in response.text
    assert "Retirer le signalement" in response.text


@pytest.mark.parametrize("hidden,status,expected", [
    (False, "uploaded", True), (True, "uploaded", False),
    (False, "pending", False), (False, None, False),
])
def test_report_photo_consultation(client, services, monkeypatch, hidden, status, expected):
    from app.domain.report_photo import UploadStatus
    import app.api.routes.report_details as details
    reads, _ = services
    original = reads.get_report
    def read(report_id, now=None):
        item = original(report_id, now)
        item.photo_status = UploadStatus(status) if status else None
        item.photo_hidden_at = "2026-10-27" if hidden else None
        return item
    reads.get_report = read
    calls = []
    class Storage:
        def create_read_url(self, **kwargs):
            calls.append(kwargs)
            return "https://s3.fr-par.scw.cloud/test/photo.jpg?signature=test"
    monkeypatch.setattr(details, "get_photo_storage", lambda: Storage())
    sign_in(client)
    response = client.get(f"/admin/reports/{REPORT_ID}")
    assert response.status_code == 200
    assert ("Ouvrir la photo" in response.text) is expected
    assert ('alt="Photographie du signalement"' in response.text) is expected
    assert bool(calls) is expected
    if expected:
        assert calls[0]["object_key"] == "reports/photo.jpg"
        assert calls[0]["expires_in"].total_seconds() == 300


def test_users_search_and_filter_preserve_pagination(client, services, monkeypatch):
    from datetime import UTC, datetime
    from app.domain.user import UserStatus
    from app.infrastructure.repositories.postgresql_admin_read_repository import PostgreSQLAdminReadRepository
    calls = []
    def search(self, page, status, query, limit=20):
        calls.append((page, status, query, limit))
        now = datetime.now(UTC)
        return [(USER_ID, "navigateur", "navigateur@nowave.test", "user", "suspended", now, now, 2)], 41
    monkeypatch.setattr(PostgreSQLAdminReadRepository, "search_users", search)
    sign_in(client)
    response = client.get("/admin/users?search=navigateur&status=suspended&page=2&limit=10")
    assert response.status_code == 200
    assert calls == [(2, UserStatus.SUSPENDED, "navigateur", 10)]
    assert 'value="suspended" aria-label="Comptes suspendus" aria-pressed="true"' in response.text
    assert "search=navigateur&amp;status=suspended&amp;page=3&amp;limit=10" in response.text
    assert f'/admin/users/{USER_ID}/reports' in response.text
    assert "Réactiver" in response.text
    assert client.get("/admin/users?search=&status=").status_code == 200
    assert client.get("/admin/users?status=invalid").status_code == 422
    assert client.get("/admin/users?search=" + "a" * 81).status_code == 422


@pytest.mark.parametrize("page,has_more", [(1, True), (2, False)])
def test_user_reports_page(client, services, monkeypatch, page, has_more):
    from datetime import UTC, datetime
    from app.infrastructure.repositories.postgresql_admin_read_repository import PostgreSQLAdminReadRepository
    calls = []
    def reports(self, user_id, requested_page):
        calls.append((user_id, requested_page))
        return [(REPORT_ID, "pollution", "active", datetime.now(UTC), "Débris près du port", "Alex")], has_more
    monkeypatch.setattr(PostgreSQLAdminReadRepository, "user_reports", reports)
    sign_in(client)
    response = client.get(f"/admin/users/{USER_ID}/reports?page={page}")
    assert response.status_code == 200
    assert calls == [(USER_ID, page)]
    assert f'/admin/reports/{REPORT_ID}' in response.text
    assert 'Signalements de Alex' in response.text
    assert 'Débris près du port' in response.text
    assert f'>{REPORT_ID}</a>' not in response.text
    assert f'<p class="identifier">{USER_ID}</p>' not in response.text
    assert ('rel="next"' in response.text) is has_more
    assert ('rel="prev"' in response.text) is (page > 1)


@pytest.mark.parametrize("status", ["", "active", "removed", "expired"])
def test_reports_search_and_status_preserve_pagination(client, services, monkeypatch, status):
    from app.domain.report import ReportStatus

    reads, _ = services
    original = reads.list_reports
    calls = []

    def filtered_reports(**kwargs):
        calls.append(kwargs)
        return original(page=kwargs["page"], limit=kwargs["limit"])

    monkeypatch.setattr(reads, "list_reports", filtered_reports)
    sign_in(client)
    response = client.get(
        "/admin/reports",
        params={"search": " bouée ", "status": status, "page": 2, "limit": 10},
    )
    assert response.status_code == 200
    assert calls == [{"page": 2, "limit": 10,
                      "status": ReportStatus(status) if status else None,
                      "search": "bouée"}]
    assert 'value="bouée"' in response.text
    assert 'status=' + status + '&amp;page=3&amp;limit=10' in response.text
    assert 'value="' + status + '" aria-label=' in response.text
    assert 'aria-pressed="true"' in response.text
    calls.clear()
    assert client.get("/admin/reports?status=invalid").status_code == 422
    assert client.get("/admin/reports", params={"search": "a" * 81}).status_code == 422
    assert not calls
