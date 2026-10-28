"""Public browser configuration; never expose server credentials or user data."""

import os
import re

from fastapi import APIRouter
from fastapi.responses import JSONResponse


router = APIRouter(prefix="/map", tags=["map"])
_PUBLIC_TOKEN = re.compile(r"pk\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+")


@router.get("/web-config")
def get_web_map_config() -> JSONResponse:
    """Only Mapbox's public token format may cross the browser boundary."""
    token = os.getenv("MAPBOX_PUBLIC_TOKEN", "").strip()
    return JSONResponse(
        content={"mapbox_token": token if _PUBLIC_TOKEN.fullmatch(token) else ""},
        headers={"Cache-Control": "no-store"},
    )
