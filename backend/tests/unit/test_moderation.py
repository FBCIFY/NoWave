from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest

from app.application.ports.moderation_repository import (
    HiddenPhotoData,
)
from app.application.services.moderation import (
    ModerationService,
)
from app.domain.errors import (
    ModerationConflictError,
    ReportNotFoundError,
)
from app.domain.moderation import (
    ModerationAction,
    ModerationActionType,
    normalize_reason,
    reactivated_user_status,
    removed_report_status,
    restored_report_status,
    suspended_user_status,
)
from app.domain.report import ReportStatus
from app.domain.report_photo import UploadStatus
from app.domain.user import User, UserRole, UserStatus


NOW = datetime(2026, 10, 12, 12, 0, tzinfo=UTC)


class FakeModerationRepository:
    def __init__(self):
        self.calls = []

    def remove_report(self, **values):
        self.calls.append(("remove_report", values))

    def restore_report(self, **values):
        self.calls.append(("restore_report", values))

    def hide_photo(self, **values):
        self.calls.append(("hide_photo", values))

        return HiddenPhotoData(
            report_id=values["report_id"],
            upload_status=UploadStatus.UPLOADED,
            size_bytes=1200,
            mime_type="image/jpeg",
            hidden_at=values["now"],
        )

    def suspend_user(self, **values):
        self.calls.append(("suspend_user", values))
        return "suspended-user"

    def reactivate_user(self, **values):
        self.calls.append(("reactivate_user", values))
        return "reactivated-user"


class FakeReportDetailRepository:
    def __init__(self, report=None):
        self.report = report

    def get_by_id(self, report_id):
        return self.report


def create_admin():
    return User(
        firebase_uid="firebase-admin",
        username="admin",
        email="admin@example.com",
        role=UserRole.ADMIN,
    )


def create_service(report=None):
    moderation_repository = FakeModerationRepository()

    service = ModerationService(
        moderation_repository=moderation_repository,
        report_detail_repository=FakeReportDetailRepository(
            report
        ),
    )

    return service, moderation_repository


def test_normalize_reason_strips_spaces():
    assert normalize_reason("  Faux signalement  ") == (
        "Faux signalement"
    )


@pytest.mark.parametrize("reason", ["", "   ", "\n\t"])
def test_normalize_reason_rejects_blank_reason(reason):
    with pytest.raises(ValueError):
        normalize_reason(reason)


@pytest.mark.parametrize(
    "status",
    [ReportStatus.ACTIVE, ReportStatus.EXPIRED],
)
def test_removed_report_status(status):
    assert removed_report_status(status) == (
        ReportStatus.REMOVED
    )


def test_removed_report_status_rejects_removed_report():
    with pytest.raises(ModerationConflictError):
        removed_report_status(ReportStatus.REMOVED)


def test_restore_before_expiry_returns_active():
    assert restored_report_status(
        ReportStatus.REMOVED,
        expires_at=NOW + timedelta(seconds=1),
        now=NOW,
    ) == ReportStatus.ACTIVE


def test_restore_at_expiry_returns_expired():
    assert restored_report_status(
        ReportStatus.REMOVED,
        expires_at=NOW,
        now=NOW,
    ) == ReportStatus.EXPIRED


@pytest.mark.parametrize(
    "status",
    [ReportStatus.ACTIVE, ReportStatus.EXPIRED],
)
def test_restore_rejects_report_not_removed(status):
    with pytest.raises(ModerationConflictError):
        restored_report_status(
            status,
            expires_at=NOW + timedelta(hours=1),
            now=NOW,
        )


def test_user_status_transitions():
    assert suspended_user_status(UserStatus.ACTIVE) == (
        UserStatus.SUSPENDED
    )
    assert reactivated_user_status(UserStatus.SUSPENDED) == (
        UserStatus.ACTIVE
    )

    with pytest.raises(ModerationConflictError):
        suspended_user_status(UserStatus.SUSPENDED)

    with pytest.raises(ModerationConflictError):
        reactivated_user_status(UserStatus.ACTIVE)


def test_moderation_action_requires_matching_target():
    with pytest.raises(ValueError):
        ModerationAction(
            admin_user_id=uuid4(),
            action=ModerationActionType.SUSPEND_USER,
            reason="Abus",
            target_report_id=uuid4(),
        )


def test_moderation_action_requires_exactly_one_target():
    with pytest.raises(ValueError):
        ModerationAction(
            admin_user_id=uuid4(),
            action=ModerationActionType.REMOVE_REPORT,
            reason="Abus",
            target_report_id=uuid4(),
            target_user_id=uuid4(),
        )


def test_moderation_action_strips_reason():
    action = ModerationAction(
        admin_user_id=uuid4(),
        action=ModerationActionType.HIDE_PHOTO,
        reason="  Photo inappropriée ",
        target_photo_report_id=uuid4(),
    )

    assert action.reason == "Photo inappropriée"


def test_remove_report_passes_admin_and_clean_reason():
    service, repository = create_service()
    admin = create_admin()
    report_id = uuid4()

    service.remove_report(
        admin=admin,
        report_id=report_id,
        reason="  Faux signalement ",
        now=NOW,
    )

    assert repository.calls == [
        (
            "remove_report",
            {
                "report_id": report_id,
                "admin_user_id": admin.id,
                "reason": "Faux signalement",
                "now": NOW,
            },
        )
    ]


def test_blank_reason_never_reaches_repository():
    service, repository = create_service()

    with pytest.raises(ValueError):
        service.remove_report(
            admin=create_admin(),
            report_id=uuid4(),
            reason="   ",
            now=NOW,
        )

    assert repository.calls == []


def test_restore_report_returns_report_detail():
    report = object()
    service, repository = create_service(report)

    result = service.restore_report(
        admin=create_admin(),
        report_id=uuid4(),
        reason="Vérifié",
        now=NOW,
    )

    assert result is report
    assert repository.calls[0][0] == "restore_report"


def test_restore_report_missing_detail_raises_not_found():
    service, _ = create_service(None)

    with pytest.raises(ReportNotFoundError):
        service.restore_report(
            admin=create_admin(),
            report_id=uuid4(),
            reason="Vérifié",
            now=NOW,
        )


def test_hide_photo_returns_photo_metadata():
    service, _ = create_service()
    report_id = uuid4()

    photo = service.hide_photo(
        admin=create_admin(),
        report_id=report_id,
        reason="Photo inappropriée",
        now=NOW,
    )

    assert photo.report_id == report_id
    assert photo.upload_status == UploadStatus.UPLOADED


def test_suspend_and_reactivate_user():
    service, repository = create_service()
    admin = create_admin()
    user_id = uuid4()

    assert service.suspend_user(
        admin=admin,
        user_id=user_id,
        reason="Abus",
        now=NOW,
    ) == "suspended-user"

    assert service.reactivate_user(
        admin=admin,
        user_id=user_id,
        reason="Suspension levée",
        now=NOW,
    ) == "reactivated-user"

    assert [call[0] for call in repository.calls] == [
        "suspend_user",
        "reactivate_user",
    ]


def test_admin_cannot_suspend_own_account():
    service, repository = create_service()
    admin = create_admin()

    with pytest.raises(ModerationConflictError):
        service.suspend_user(
            admin=admin,
            user_id=admin.id,
            reason="Test",
            now=NOW,
        )

    assert repository.calls == []


def test_now_requires_timezone():
    service, _ = create_service()

    with pytest.raises(ValueError):
        service.remove_report(
            admin=create_admin(),
            report_id=uuid4(),
            reason="Faux signalement",
            now=datetime(2026, 10, 12, 12, 0),
        )
