from datetime import timedelta
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
from app.application.ports.report_detail_repository import (
    ReportDetailData,
)
from app.application.services.get_report_detail import (
    GetReportDetail,
)
from app.dependencies.photo_storage import get_photo_storage
from app.domain.report_photo import UploadStatus
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
    identity: dict = Depends(get_current_identity),
):
    del identity

    repository = PostgreSQLReportDetailRepository()

    service = GetReportDetail(
        report_detail_repository=repository,
    )

    report = service.execute(
        report_id=report_id,
    )

    return report_detail_response(report)


def photo_read_url(
    report: ReportDetailData,
) -> str | None:
    """A hidden photo never receives a new read URL, even for an admin."""
    if (
        report.photo_status != UploadStatus.UPLOADED
        or report.photo_object_key is None
        or report.photo_hidden_at is not None
    ):
        return None

    return get_photo_storage().create_read_url(
        object_key=report.photo_object_key,
        expires_in=timedelta(minutes=5),
    )


def report_detail_response(
    report: ReportDetailData,
) -> ReportDetailResponse:
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
            url=photo_read_url(report),
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
