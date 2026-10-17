"""Lazily constructed per-process providers; no network access at import time."""

import os

from app.application.services.marine_tiles import MarineTileService
from app.infrastructure.marine.ign import IgnPortProvider
from app.infrastructure.marine.http import MarineHTTP
from app.infrastructure.marine.providers import (
    NoaaProvider,
    OpenWatersProvider,
    ShomProvider,
    ShortbreadProvider,
)

_http = None
_service = None


def get_marine_service():
    global _http, _service
    if _service is None:
        _http = MarineHTTP()
        disabled = set(os.getenv("MARINE_DISABLED_PROVIDERS", "").split(","))
        providers = [
            OpenWatersProvider(_http),
            ShortbreadProvider(_http, os.getenv("MARINE_SHORTBREAD_URL")),
            ShomProvider(_http),
            IgnPortProvider(_http),
            NoaaProvider(_http),
        ]
        _service = MarineTileService(p for p in providers if p.id not in disabled)
    return _service


async def close_marine_service():
    global _http, _service
    if _http is not None:
        await _http.close()
    _http = _service = None
