from fastapi import APIRouter

from app.api.routes.map_tiles import router as map_tiles_router
from app.api.routes.reports import router as reports_router
from app.api.routes.users import router as users_router


router = APIRouter(prefix="/api/v1")

router.include_router(users_router)
router.include_router(reports_router)
router.include_router(map_tiles_router)
