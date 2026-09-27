from typing import Annotated
import os

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse

from app.dependencies.container import get_database_ready


router = APIRouter()


@router.get("/version")
def version():
    return {"service": "nowave-api", "version": os.getenv("NOWAVE_VERSION", "development")}


@router.get("/health")
def health_check():
    return {"status": "ok"}


@router.get("/health/ready", responses={503: {"description": "Database unavailable"}})
def readiness_check(database_ready: Annotated[bool, Depends(get_database_ready)]):
    if not database_ready:
        return JSONResponse(
            status_code=503,
            content={"status": "not_ready", "database": "unavailable"},
        )
    return {"status": "ready", "database": "ok"}
