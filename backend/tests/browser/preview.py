"""Read-only visual preview on loopback, with synthetic data and no DB/Firebase.

Run from the repository root: PYTHONPATH=backend python backend/tests/browser/preview.py
The normal browser login accepts admin@nowave.test / preview-only.
"""

import argparse
from datetime import UTC, datetime, timedelta
import json
from http.cookies import SimpleCookie
import os
from pathlib import Path
import secrets
import tarfile
import tempfile
from uuid import UUID


class PreviewCookiesMiddleware:
    """HTTP loopback cookies for synthetic previews, including Safari.

    Production keeps its __Host-/Secure cookies. The preview uses isolated
    names and passes their values through the unchanged auth and CSRF checks.
    """

    def __init__(self, app):
        from app.web.csrf import CSRF_COOKIE
        from app.web.errors import SESSION_COOKIE
        self.app = app
        self.cookie_names = {
            "nowave_preview_admin_csrf": CSRF_COOKIE,
            "nowave_preview_admin_session": SESSION_COOKIE,
        }

    async def __call__(self, scope, receive, send):
        from starlette.requests import Request
        from starlette.responses import JSONResponse
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        request = Request(scope)
        if request.url.hostname not in {"127.0.0.1", "localhost", "::1"}:
            return await JSONResponse(
                {"detail": "L’aperçu est réservé à la boucle locale."}, status_code=403,
            )(scope, receive, send)

        # Never reuse real admin cookies for a synthetic session. Only the
        # separate preview cookies are visible to the regular security code.
        forwarded = SimpleCookie()
        for preview_name, protected_name in self.cookie_names.items():
            if preview_name in request.cookies:
                forwarded[protected_name] = request.cookies[preview_name]
        headers = [(key, value) for key, value in scope["headers"] if key.lower() != b"cookie"]
        if forwarded:
            headers.append((b"cookie", forwarded.output(header="", sep="; ").strip().encode("latin-1")))
        scope = {**scope, "headers": headers}
        reverse_names = {value: key for key, value in self.cookie_names.items()}

        async def send_preview(message):
            if message["type"] == "http.response.start":
                headers = []
                for key, value in message.get("headers", []):
                    if key.lower() == b"set-cookie":
                        original = SimpleCookie()
                        original.load(value.decode("latin-1"))
                        for protected_name, preview_name in reverse_names.items():
                            if protected_name in original:
                                source = original[protected_name]
                                local = SimpleCookie()
                                local[preview_name] = source.value
                                for attribute, setting in source.items():
                                    if attribute != "secure" and setting:
                                        local[preview_name][attribute] = setting
                                value = local.output(header="").strip().encode("latin-1")
                                break
                    headers.append((key, value))
                message = {**message, "headers": headers}
            await send(message)

        await self.app(scope, receive, send_preview)


def configure_preview():
    if os.getenv("NOWAVE_ENV") == "production":
        raise RuntimeError("Preview fixtures cannot run in production mode")

    from fastapi.responses import JSONResponse
    from app.main import app
    from app.api.routes.map_web_config import _PUBLIC_TOKEN
    from app.api.routes.public_observations import get_public_observation_reader
    from app.application.ports.public_observation_reader import PublicObservation
    from app.application.ports.admin_read_repository import (
        AdminReportDetailData, AdminUserData, ModerationActionData,
    )
    from app.dependencies.admin_web_session import get_admin_web_session
    from app.domain.boat import BoatType
    from app.domain.errors import InvalidCredentialsError, InvalidSessionError, ReportNotFoundError
    from app.domain.moderation import ModerationActionType
    from app.domain.pagination import Page
    from app.domain.report import ReportCategory, ReportPositioningMode, ReportStatus
    from app.domain.user import User, UserRole, UserStatus
    from app.web.routes import admin_pages

    config = os.getenv("NOWAVE_MAPBOX_CONFIG")
    token = (json.loads(Path(config).expanduser().read_text())["MAPBOX_ACCESS_TOKEN"]
             if config else os.getenv("MAPBOX_PUBLIC_TOKEN", "")).strip()
    if token and not _PUBLIC_TOKEN.fullmatch(token):
        raise ValueError("Preview accepts a public pk.* Mapbox token only")
    os.environ["MAPBOX_PUBLIC_TOKEN"] = token

    now = datetime.now(UTC)
    admin = User(id=UUID(int=1), firebase_uid="preview-admin", username="Équipe NoWave",
                 email="admin@nowave.test", role=UserRole.ADMIN)
    cookie = secrets.token_urlsafe(32)

    class Session:
        def sign_in(self, email, password):
            if (email, password) != ("admin@nowave.test", "preview-only"):
                raise InvalidCredentialsError()
            return cookie

        def authenticate(self, value):
            if value != cookie:
                raise InvalidSessionError()
            return admin

    users = [AdminUserData(
        id=UUID(int=i + 10), username=name, email=f"navigateur{i}@nowave.test",
        role=UserRole.USER, status=UserStatus.SUSPENDED if i == 2 else UserStatus.ACTIVE,
        created_at=now - timedelta(days=42 + i), updated_at=now, reports_count=1,
    ) for i, name in enumerate(["Alex", "Léa", "Camille"])]
    # Same synthetic scenarios and offshore locations as web/src/data.js.
    reports = [AdminReportDetailData(
        id=UUID(int=i + 100), category=category, positioning_mode=ReportPositioningMode.MANUAL,
        description=description, longitude=longitude, latitude=latitude,
        observed_at=now - timedelta(minutes=20 + i * 13),
        expires_at=now + timedelta(hours=23), status=ReportStatus.ACTIVE, version=1,
        author_deleted=False, author_username=users[i].username,
        boat_name=["Aurore", "Écume", "Alizé"][i], boat_type=BoatType.SAILBOAT,
        photo_status=None, photo_object_key=None, photo_hidden_at=None, removed_at=None,
        author_id=users[i].id, author_email=users[i].email, author_status=users[i].status,
    ) for i, (category, description, longitude, latitude) in enumerate([
        (ReportCategory.OBSTRUCTION, "Un conteneur à la dérive au large de Singapour.", 103.95, 1.21),
        (ReportCategory.MARINE_ANIMAL, "Une baleine observée au large, en direction de l’est.", -28.7, 38.33),
        (ReportCategory.POLLUTION, "Débris plastiques dispersés en surface.", 178.4, -18.29),
    ])]
    actions = [ModerationActionData(
        id=UUID(int=200), action=ModerationActionType.REMOVE_REPORT,
        admin_user_id=admin.id, admin_username=admin.username, target_user_id=None,
        target_report_id=reports[0].id, target_photo_report_id=None,
        reason="Doublon — entrée synthétique pour l’aperçu.", previous_status="active",
        new_status="removed", created_at=now - timedelta(hours=1),
    )]

    def make_page(items, number, limit):
        start = (number - 1) * limit
        return Page(items=items[start:start + limit], page=number, limit=limit, total=len(items))

    class Reads:
        def list_reports(self, page=1, limit=20, status=None, now=None):
            return make_page([r for r in reports if status is None or r.status == status], page, limit)

        def get_report(self, report_id, now=None):
            for report in reports:
                if report.id == report_id:
                    return report
            raise ReportNotFoundError()

        def list_users(self, page=1, limit=20, status=None):
            return make_page([u for u in users if status is None or u.status == status], page, limit)

        def list_moderation_actions(self, page=1, limit=20, report_id=None):
            matching = [action for action in actions if report_id is None
                        or report_id in (action.target_report_id, action.target_photo_report_id)]
            return make_page(matching, page, limit)

        def map_reports(self, west, south, east, north, limit=1000):
            return [(r.id, r.longitude, r.latitude, r.category.value, r.status.value)
                    for r in reports if west <= r.longitude <= east and south <= r.latitude <= north], False

        def search_users(self, page, status, search):
            found = [u for u in users if (status is None or u.status == status)
                     and search.casefold() in f"{u.username} {u.email}".casefold()]
            return [(u.id, u.username, u.email, u.role.value, u.status.value,
                     u.created_at, u.updated_at, u.reports_count)
                    for u in make_page(found, page, 20).items], len(found)

        def user_reports(self, user_id, page):
            found = [r for r in reports if r.author_id == user_id]
            return [(r.id, r.category.value, r.status.value, r.observed_at)
                    for r in make_page(found, page, 20).items], len(found) > page * 20

    reads = Reads()

    class Observations:
        def list_active(self, query):
            current = datetime.now(UTC)
            found = []
            for report in reports:
                longitude_matches = (query.west <= report.longitude <= query.east
                                     if query.west <= query.east
                                     else report.longitude >= query.west or report.longitude <= query.east)
                if (report.status != ReportStatus.ACTIVE or report.expires_at <= current
                        or report.removed_at is not None or not longitude_matches
                        or not query.south <= report.latitude <= query.north
                        or query.category is not None and report.category != query.category
                        or query.q.casefold() not in f"{report.description or ''} {report.author_username or ''}".casefold()
                        or query.after is not None and (report.observed_at, report.id) >= query.after):
                    continue
                found.append(PublicObservation(
                    id=report.id, category=report.category,
                    longitude=report.longitude, latitude=report.latitude,
                    observed_at=report.observed_at, expires_at=report.expires_at,
                    description=report.description, author_username=report.author_username,
                ))
            return sorted(found, key=lambda report: (report.observed_at, report.id), reverse=True)[:query.limit + 1]

    app.dependency_overrides[get_public_observation_reader] = Observations
    app.dependency_overrides[get_admin_web_session] = Session
    app.dependency_overrides[admin_pages.get_admin_read_service] = lambda: reads
    admin_pages.PostgreSQLAdminReadRepository = lambda: reads

    app.add_middleware(PreviewCookiesMiddleware)

    @app.middleware("http")
    async def preview_read_only(request, call_next):
        path = request.url.path
        if (not path.startswith(("/admin", "/api/v1/map/"))
                or path.startswith("/api/v1/map/tiles/")):
            return JSONResponse({"detail": "Route absente de l’aperçu."}, status_code=404)
        if request.method not in {"GET", "HEAD"} and path not in {
            "/admin/login", "/admin/logout",
        }:
            return JSONResponse({"detail": "Aperçu local : modifications désactivées."}, status_code=409)
        response = await call_next(request)
        response.headers["X-NoWave-Preview"] = "synthetic-read-only"
        return response

    return app


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()
    app = configure_preview()
    from fastapi.staticfiles import StaticFiles
    import uvicorn

    with tempfile.TemporaryDirectory(prefix="nowave-web-preview-") as directory:
        bundle = Path(__file__).resolve().parents[3] / "deploy/marine/gebco-2026-v2.tar.gz"
        with tarfile.open(bundle) as archive:
            archive.extractall(directory, filter="data")
        app.mount("/api/v1/map/seafloor", StaticFiles(directory=directory))
        print(f"Aperçu synthétique : http://127.0.0.1:{args.port}/admin/login", flush=True)
        print("Connexion locale : admin@nowave.test / preview-only", flush=True)
        uvicorn.run(app, host="127.0.0.1", port=args.port, log_level="warning")


if __name__ == "__main__":
    main()
