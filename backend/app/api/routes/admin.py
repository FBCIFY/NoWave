from uuid import UUID

from fastapi import APIRouter, Depends, Query, status
from pydantic import BaseModel

from app.api.dependencies.auth import get_current_admin
from app.api.routes.report_details import (
    photo_read_url,
    report_detail_response,
)
from app.api.schemas.admin import (
    AdminReportAuthorResponse,
    AdminReportDetailResponse,
    AdminReportPhotoResponse,
    AdminReportSummaryResponse,
    AdminUserResponse,
    ModerationActionResponse,
    ModerationReasonRequest,
    PaginatedResponse,
    PhotoHideRequest,
    ReportRestoreRequest,
    UserStatusUpdateRequest,
)
from app.api.schemas.report import GeoJSONPoint, PhotoMetadataResponse
from app.api.schemas.report_detail import (
    ReportDetailBoatResponse,
    ReportDetailResponse,
)
from app.api.schemas.user import UserProfileResponse
from app.application.ports.admin_read_repository import (
    AdminReportDetailData,
)
from app.application.services.admin_reads import AdminReadService
from app.application.services.moderation import ModerationService
from app.domain.pagination import (
    DEFAULT_PAGE_LIMIT,
    MAX_PAGE,
    MAX_PAGE_LIMIT,
    Page,
)
from app.domain.report import ReportStatus
from app.domain.user import User, UserStatus
from app.infrastructure.repositories.postgresql_admin_read_repository import (
    PostgreSQLAdminReadRepository,
)
from app.infrastructure.repositories.postgresql_moderation_repository import (
    PostgreSQLModerationRepository,
)
from app.infrastructure.repositories.postgresql_report_detail_repository import (
    PostgreSQLReportDetailRepository,
)


router = APIRouter(
    prefix="/admin",
    tags=["admin"],
)


def moderation_service():
    return ModerationService(
        moderation_repository=PostgreSQLModerationRepository(),
        report_detail_repository=PostgreSQLReportDetailRepository(),
    )


def admin_read_service():
    return AdminReadService(
        admin_read_repository=PostgreSQLAdminReadRepository(),
    )


@router.patch(
    "/reports/{report_id}",
    response_model=ReportDetailResponse,
)
def restore_report(
    report_id: UUID,
    request: ReportRestoreRequest,
    admin: User = Depends(get_current_admin),
):
    report = moderation_service().restore_report(
        admin=admin,
        report_id=report_id,
        reason=request.reason,
    )

    return report_detail_response(report)


@router.delete(
    "/reports/{report_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
def remove_report(
    report_id: UUID,
    request: ModerationReasonRequest,
    admin: User = Depends(get_current_admin),
):
    moderation_service().remove_report(
        admin=admin,
        report_id=report_id,
        reason=request.reason,
    )


@router.patch(
    "/reports/{report_id}/photo",
    response_model=PhotoMetadataResponse,
)
def hide_report_photo(
    report_id: UUID,
    request: PhotoHideRequest,
    admin: User = Depends(get_current_admin),
):
    photo = moderation_service().hide_photo(
        admin=admin,
        report_id=report_id,
        reason=request.reason,
    )

    return PhotoMetadataResponse(
        report_id=photo.report_id,
        upload_status=photo.upload_status,
        size_bytes=photo.size_bytes,
        mime_type=photo.mime_type,
    )


@router.patch(
    "/users/{user_id}",
    response_model=UserProfileResponse,
)
def update_user_status(
    user_id: UUID,
    request: UserStatusUpdateRequest,
    admin: User = Depends(get_current_admin),
):
    service = moderation_service()

    if request.status == UserStatus.SUSPENDED:
        return service.suspend_user(
            admin=admin,
            user_id=user_id,
            reason=request.reason,
        )

    return service.reactivate_user(
        admin=admin,
        user_id=user_id,
        reason=request.reason,
    )


@router.get(
    "/reports",
    response_model=PaginatedResponse[AdminReportSummaryResponse],
)
def list_reports(
    page: int = Query(default=1, ge=1, le=MAX_PAGE),
    limit: int = Query(
        default=DEFAULT_PAGE_LIMIT,
        ge=1,
        le=MAX_PAGE_LIMIT,
    ),
    report_status: ReportStatus | None = Query(
        default=None,
        alias="status",
    ),
    admin: User = Depends(get_current_admin),
):
    del admin

    reports = admin_read_service().list_reports(
        page=page,
        limit=limit,
        status=report_status,
    )

    return page_response(reports, AdminReportSummaryResponse)


@router.get(
    "/reports/{report_id}",
    response_model=AdminReportDetailResponse,
)
def get_report(
    report_id: UUID,
    admin: User = Depends(get_current_admin),
):
    del admin

    report = admin_read_service().get_report(
        report_id=report_id,
    )

    return admin_report_detail_response(report)


@router.get(
    "/users",
    response_model=PaginatedResponse[AdminUserResponse],
)
def list_users(
    page: int = Query(default=1, ge=1, le=MAX_PAGE),
    limit: int = Query(
        default=DEFAULT_PAGE_LIMIT,
        ge=1,
        le=MAX_PAGE_LIMIT,
    ),
    user_status: UserStatus | None = Query(
        default=None,
        alias="status",
    ),
    admin: User = Depends(get_current_admin),
):
    del admin

    users = admin_read_service().list_users(
        page=page,
        limit=limit,
        status=user_status,
    )

    return page_response(users, AdminUserResponse)


@router.get(
    "/moderation-actions",
    response_model=PaginatedResponse[ModerationActionResponse],
)
def list_moderation_actions(
    page: int = Query(default=1, ge=1, le=MAX_PAGE),
    limit: int = Query(
        default=DEFAULT_PAGE_LIMIT,
        ge=1,
        le=MAX_PAGE_LIMIT,
    ),
    admin: User = Depends(get_current_admin),
):
    del admin

    actions = admin_read_service().list_moderation_actions(
        page=page,
        limit=limit,
    )

    return page_response(actions, ModerationActionResponse)


def page_response(
    page: Page,
    item_response: type[BaseModel],
) -> PaginatedResponse:
    return PaginatedResponse(
        items=[
            item_response.model_validate(item)
            for item in page.items
        ],
        page=page.page,
        limit=page.limit,
        total=page.total,
        pages=page.pages,
    )


def admin_report_detail_response(
    report: AdminReportDetailData,
) -> AdminReportDetailResponse:
    boat = None

    if report.boat_type is not None:
        boat = ReportDetailBoatResponse(
            name=report.boat_name,
            boat_type=report.boat_type,
        )

    photo = None

    if report.photo_status is not None:
        photo = AdminReportPhotoResponse(
            status=report.photo_status,
            url=photo_read_url(report),
            hidden_at=report.photo_hidden_at,
        )

    return AdminReportDetailResponse(
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
        removed_at=report.removed_at,
        author=AdminReportAuthorResponse(
            id=report.author_id,
            username=report.author_username,
            email=report.author_email,
            status=report.author_status,
            deleted=report.author_deleted,
        ),
        boat=boat,
        photo=photo,
    )
