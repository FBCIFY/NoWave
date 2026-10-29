"""Production boundaries; secrets never enter logs or application responses."""

import json
import os
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from starlette.middleware.trustedhost import TrustedHostMiddleware

from app.config.settings import ConfigurationError, get_settings


def is_production() -> bool:
    return os.getenv("NOWAVE_ENV") == "production"


def configure_production(app: FastAPI) -> None:
    if not is_production():
        return
    settings = get_settings()
    settings.require_database_url()
    settings.require_photo_storage()
    try:
        credentials = json.loads(
            Path(os.environ["GOOGLE_APPLICATION_CREDENTIALS"]).read_text()
        )
        valid = (
            credentials.get("type") == "service_account"
            and credentials.get("project_id") == os.environ["GOOGLE_CLOUD_PROJECT"]
            and bool(credentials.get("private_key"))
        )
    except (KeyError, OSError, ValueError):
        valid = False
    if not valid:
        raise ConfigurationError(
            "A matching Firebase service account is required in production"
        )

    app.add_middleware(
        TrustedHostMiddleware,
        allowed_hosts=[
            "no-wave.fr",
            "www.no-wave.fr",
            "api.no-wave.fr",
            "127.0.0.1",
            "localhost",
        ],
        www_redirect=False,
    )

    @app.middleware("http")
    async def reject_foreign_origin(request: Request, call_next):
        origin = request.headers.get("origin")
        if origin and origin not in {
            "https://no-wave.fr",
            "https://www.no-wave.fr",
            "https://api.no-wave.fr",
        }:
            return JSONResponse(
                status_code=403, content={"detail": "Origin not allowed"}
            )
        return await call_next(request)
