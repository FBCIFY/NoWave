from datetime import UTC, datetime
from enum import Enum
from uuid import UUID, uuid4


class DevicePlatform(str, Enum):
    ANDROID = "android"
    IOS = "ios"


class Device:
    def __init__(
        self,
        user_id: UUID,
        installation_id: UUID,
        platform: DevicePlatform,
        fcm_token: str | None = None,
        id: UUID | None = None,
        is_active: bool = True,
        last_seen_at: datetime | None = None,
    ):
        if user_id is None:
            raise ValueError("user_id is required")

        if installation_id is None:
            raise ValueError("installation_id is required")

        try:
            platform = DevicePlatform(platform)
        except ValueError as error:
            raise ValueError("invalid device platform") from error

        if fcm_token is not None and not fcm_token.strip():
            raise ValueError("fcm_token cannot be empty")

        self.id = id if id is not None else uuid4()
        self.user_id = user_id
        self.installation_id = installation_id
        self.platform = platform
        self.fcm_token = (
            fcm_token.strip()
            if fcm_token is not None
            else None
        )
        self.is_active = is_active
        self.last_seen_at = (
            last_seen_at
            if last_seen_at is not None
            else datetime.now(UTC)
        )
