from collections.abc import Callable
from datetime import datetime
from uuid import UUID

from psycopg.errors import CheckViolation

from app.application.ports.moderation_repository import (
    HiddenPhotoData,
    ModerationRepository,
)
from app.domain.errors import (
    AdminRequiredError,
    ModerationConflictError,
    PhotoNotFoundError,
    ReportNotFoundError,
    UserNotFoundError,
)
from app.domain.moderation import (
    ModerationAction,
    ModerationActionType,
    reactivated_user_status,
    removed_report_status,
    restored_report_status,
    suspended_user_status,
)
from app.domain.report import ReportStatus
from app.domain.report_photo import UploadStatus
from app.domain.user import User, UserRole, UserStatus
from app.infrastructure.database.connection import database_connection


# Message of nowave.guard_audit() when the administrator is not active.
INACTIVE_ADMIN_MESSAGE = "An active administrator is required"


class PostgreSQLModerationRepository(ModerationRepository):
    def remove_report(
        self,
        report_id: UUID,
        admin_user_id: UUID,
        reason: str,
        now: datetime,
    ) -> ModerationAction:
        return self._change_report_status(
            report_id=report_id,
            admin_user_id=admin_user_id,
            reason=reason,
            now=now,
            action_type=ModerationActionType.REMOVE_REPORT,
            next_status=lambda status, expires_at: (
                removed_report_status(status)
            ),
        )

    def restore_report(
        self,
        report_id: UUID,
        admin_user_id: UUID,
        reason: str,
        now: datetime,
    ) -> ModerationAction:
        return self._change_report_status(
            report_id=report_id,
            admin_user_id=admin_user_id,
            reason=reason,
            now=now,
            action_type=ModerationActionType.RESTORE_REPORT,
            next_status=lambda status, expires_at: (
                restored_report_status(status, expires_at, now)
            ),
        )

    def hide_photo(
        self,
        report_id: UUID,
        admin_user_id: UUID,
        reason: str,
        now: datetime,
    ) -> HiddenPhotoData:
        try:
            with database_connection() as connection:
                with connection.cursor() as cursor:
                    cursor.execute(
                        """
                        SELECT
                            upload_status,
                            size_bytes,
                            mime_type,
                            hidden_at
                        FROM nowave.report_photos
                        WHERE report_id = %s
                        FOR UPDATE
                        """,
                        (report_id,),
                    )

                    row = cursor.fetchone()

                    if row is None:
                        cursor.execute(
                            """
                            SELECT 1
                            FROM nowave.reports
                            WHERE id = %s
                            """,
                            (report_id,),
                        )

                        if cursor.fetchone() is None:
                            raise ReportNotFoundError(
                                "report not found"
                            )

                        raise PhotoNotFoundError(
                            "report has no photo"
                        )

                    upload_status = UploadStatus(row[0])

                    if row[3] is not None:
                        raise ModerationConflictError(
                            "photo is already hidden"
                        )

                    if upload_status != UploadStatus.UPLOADED:
                        raise ModerationConflictError(
                            "photo is not uploaded"
                        )

                    cursor.execute(
                        """
                        UPDATE nowave.report_photos
                        SET
                            hidden_at = %s,
                            updated_at = %s
                        WHERE report_id = %s
                        """,
                        (
                            now,
                            now,
                            report_id,
                        ),
                    )

                    self._insert_action(
                        cursor,
                        ModerationAction(
                            admin_user_id=admin_user_id,
                            action=ModerationActionType.HIDE_PHOTO,
                            reason=reason,
                            target_photo_report_id=report_id,
                            created_at=now,
                        ),
                    )
        except CheckViolation as error:
            self._raise_admin_required(error)

        return HiddenPhotoData(
            report_id=report_id,
            upload_status=upload_status,
            size_bytes=row[1],
            mime_type=row[2],
            hidden_at=now,
        )

    def suspend_user(
        self,
        user_id: UUID,
        admin_user_id: UUID,
        reason: str,
        now: datetime,
    ) -> User:
        return self._change_user_status(
            user_id=user_id,
            admin_user_id=admin_user_id,
            reason=reason,
            now=now,
            action_type=ModerationActionType.SUSPEND_USER,
            next_status=suspended_user_status,
        )

    def reactivate_user(
        self,
        user_id: UUID,
        admin_user_id: UUID,
        reason: str,
        now: datetime,
    ) -> User:
        return self._change_user_status(
            user_id=user_id,
            admin_user_id=admin_user_id,
            reason=reason,
            now=now,
            action_type=ModerationActionType.REACTIVATE_USER,
            next_status=reactivated_user_status,
        )

    def _change_report_status(
        self,
        report_id: UUID,
        admin_user_id: UUID,
        reason: str,
        now: datetime,
        action_type: ModerationActionType,
        next_status: Callable[[ReportStatus, datetime], ReportStatus],
    ) -> ModerationAction:
        try:
            with database_connection() as connection:
                with connection.cursor() as cursor:
                    cursor.execute(
                        """
                        SELECT status, expires_at
                        FROM nowave.reports
                        WHERE id = %s
                        FOR UPDATE
                        """,
                        (report_id,),
                    )

                    row = cursor.fetchone()

                    if row is None:
                        raise ReportNotFoundError(
                            "report not found"
                        )

                    previous_status = ReportStatus(row[0])
                    new_status = next_status(
                        previous_status,
                        row[1],
                    )

                    # Version and expires_at stay unchanged: moderation
                    # does not trigger new alerts nor extend a report.
                    cursor.execute(
                        """
                        UPDATE nowave.reports
                        SET
                            status = %s,
                            removed_at = %s,
                            updated_at = %s
                        WHERE id = %s
                        """,
                        (
                            new_status.value,
                            (
                                now
                                if new_status == ReportStatus.REMOVED
                                else None
                            ),
                            now,
                            report_id,
                        ),
                    )

                    action = ModerationAction(
                        admin_user_id=admin_user_id,
                        action=action_type,
                        reason=reason,
                        target_report_id=report_id,
                        previous_status=previous_status.value,
                        new_status=new_status.value,
                        created_at=now,
                    )

                    self._insert_action(cursor, action)
        except CheckViolation as error:
            self._raise_admin_required(error)

        return action

    def _change_user_status(
        self,
        user_id: UUID,
        admin_user_id: UUID,
        reason: str,
        now: datetime,
        action_type: ModerationActionType,
        next_status: Callable[[UserStatus], UserStatus],
    ) -> User:
        try:
            with database_connection() as connection:
                with connection.cursor() as cursor:
                    cursor.execute(
                        """
                        SELECT status
                        FROM nowave.users
                        WHERE id = %s
                        FOR UPDATE
                        """,
                        (user_id,),
                    )

                    row = cursor.fetchone()

                    if row is None:
                        raise UserNotFoundError(
                            "user not found"
                        )

                    previous_status = UserStatus(row[0])
                    new_status = next_status(previous_status)

                    cursor.execute(
                        """
                        UPDATE nowave.users
                        SET
                            status = %s,
                            updated_at = %s
                        WHERE id = %s
                        RETURNING
                            id,
                            firebase_uid,
                            username,
                            email,
                            date_of_birth,
                            nationality,
                            role,
                            status,
                            show_user_name,
                            show_boat_info,
                            notifications_enabled,
                            created_at,
                            updated_at
                        """,
                        (
                            new_status.value,
                            now,
                            user_id,
                        ),
                    )

                    user_row = cursor.fetchone()

                    self._insert_action(
                        cursor,
                        ModerationAction(
                            admin_user_id=admin_user_id,
                            action=action_type,
                            reason=reason,
                            target_user_id=user_id,
                            previous_status=previous_status.value,
                            new_status=new_status.value,
                            created_at=now,
                        ),
                    )
        except CheckViolation as error:
            self._raise_admin_required(error)

        return self._row_to_user(user_row)

    def _insert_action(
        self,
        cursor,
        action: ModerationAction,
    ) -> None:
        cursor.execute(
            """
            INSERT INTO nowave.moderation_actions (
                id,
                admin_user_id,
                target_user_id,
                target_report_id,
                target_photo_report_id,
                action,
                reason,
                previous_status,
                new_status,
                created_at
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                action.id,
                action.admin_user_id,
                action.target_user_id,
                action.target_report_id,
                action.target_photo_report_id,
                action.action.value,
                action.reason,
                action.previous_status,
                action.new_status,
                action.created_at,
            ),
        )

    def _raise_admin_required(
        self,
        error: CheckViolation,
    ) -> None:
        if error.diag.message_primary == INACTIVE_ADMIN_MESSAGE:
            raise AdminRequiredError(
                "an active administrator is required"
            ) from error

        raise error

    def _row_to_user(self, row) -> User:
        return User(
            id=row[0],
            firebase_uid=row[1],
            username=row[2],
            email=row[3],
            date_of_birth=row[4],
            nationality=row[5],
            role=UserRole(row[6]),
            status=UserStatus(row[7]),
            show_user_name=row[8],
            show_boat_info=row[9],
            notifications_enabled=row[10],
            created_at=row[11],
            updated_at=row[12],
        )
