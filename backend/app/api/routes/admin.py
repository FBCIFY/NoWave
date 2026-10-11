from uuid import UUID

from fastapi import APIRouter, Depends, status

from app.api.dependencies.auth import get_current_admin
from app.api.routes.report_details import report_detail_response
from app.api.schemas.admin import (
    ModerationReasonRequest,
    PhotoHideRequest,
    ReportRestoreRequest,
    UserStatusUpdateRequest,
)
from app.api.schemas.report import PhotoMetadataResponse
from app.api.schemas.report_detail import ReportDetailResponse
from app.api.schemas.user import UserProfileResponse
from app.application.services.moderation import ModerationService
from app.domain.user import User, UserStatus
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
