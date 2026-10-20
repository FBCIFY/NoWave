"""Lazily constructed per-process providers; no network access at import time."""

import os

from app.application.services.marine_tiles import MarineTileService
from app.infrastructure.marine.emodnet_depths import EmodnetDepthProvider
from app.infrastructure.marine.ign import IgnPortProvider
from app.infrastructure.marine.harbours import HarbourProvider
from app.infrastructure.marine.http import MarineHTTP
from app.infrastructure.marine.coastline import CoastlineMask
from app.infrastructure.marine.hydro_providers import (
    ShomHazardProvider,
    EmodnetContourProvider,
    NoaaHydroProvider,
    NoaaSoundingProvider,
)
from app.infrastructure.marine.providers import (
    NoaaProvider,
    OpenWatersProvider,
    ShomProvider,
    ShortbreadProvider,
)

_http = None
_service = None
_depths = None
_sounding_http = None
_coastline = None


def get_marine_service():
    global _http, _service, _depths, _sounding_http, _coastline
    if _service is None:
        _http = MarineHTTP()
        _coastline = CoastlineMask(_http, os.getenv("MARINE_SHORTBREAD_URL"))
        _depths = EmodnetDepthProvider()
        _sounding_http = MarineHTTP(persistent_cache=False)
        disabled = set(os.getenv("MARINE_DISABLED_PROVIDERS", "").split(","))
        providers = [
            ShomHazardProvider(_http),
            _depths,
            EmodnetContourProvider(_http),
            NoaaHydroProvider(_http),
            NoaaSoundingProvider(_sounding_http),
            OpenWatersProvider(_http),
            HarbourProvider(_http),
            ShortbreadProvider(_http, os.getenv("MARINE_SHORTBREAD_URL")),
            ShomProvider(_http),
            IgnPortProvider(_http),
            NoaaProvider(_http),
        ]
        _service = MarineTileService(p for p in providers if p.id not in disabled)
    return _service


def get_coastline_mask():
    get_marine_service()
    return _coastline


async def close_marine_service():
    global _http, _service, _depths, _sounding_http, _coastline
    if _http is not None:
        await _http.close()
    if _depths is not None:
        await _depths.close()
    if _sounding_http is not None:
        await _sounding_http.close()
    _http = _service = _depths = _sounding_http = None
    _coastline = None
