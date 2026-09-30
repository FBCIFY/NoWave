from uuid import UUID

from fastapi import APIRouter, Depends

from app.api.dependencies.auth import get_current_identity
from app.api.schemas.report import GeoJSONPoint
from app.api.schemas.report_detail import (
    ReportDetailAuthorResponse,
    ReportDetailBoatResponse,
    ReportDetailPhotoResponse,
    ReportDetailResponse,
)
from app.application.services.get_report_detail import (
    GetReportDetail,
)
from app.infrastructure.repositories.postgresql_report_detail_repository import (
    PostgreSQLReportDetailRepository,
)


router = APIRouter(
    prefix="/reports",
    tags=["reports"],
)


@router.get(
    "/{report_id}",
    response_model=ReportDetailResponse,
)
def get_report_detail(
    report_id: UUID,
    identity: dict = Depends(
        get_current_identity
    ),
):
    del identity

    repository = PostgreSQLReportDetailRepository()

    service = GetReportDetail(
        report_detail_repository=repository,
    )

    report = service.execute(
        report_id=report_id,
    )

    author = None

    if report.author_deleted:
        author = ReportDetailAuthorResponse(
            username=None,
            deleted=True,
        )
    elif report.author_username is not None:
        author = ReportDetailAuthorResponse(
            username=report.author_username,
            deleted=False,
        )

    boat = None

    if report.boat_type is not None:
        boat = ReportDetailBoatResponse(
            name=report.boat_name,
            boat_type=report.boat_type,
        )

    photo = None

    if report.photo_status is not None:
        photo = ReportDetailPhotoResponse(
            status=report.photo_status,
            url=None,
        )

    return ReportDetailResponse(
        id=report.id,
        version=report.version,
        category=report.category,
        description=report.description,
        positioning_mode=report.positioning_mode,
        final_position=GeoJSONPoint(
            type="Point",
            coordinates=[
                report.longitude,
                report.latitude,
            ],
        ),
        status=report.status,
        observed_at=report.observed_at,
        expires_at=report.expires_at,
        author=author,
        boat=boat,
        photo=photo,
    )
