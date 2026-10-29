from app.application.ports.photo_storage import PhotoStoragePort
from app.config.settings import get_settings
from app.infrastructure.adapters.scaleway_photo_storage_adapter import (
    ScalewayPhotoStorageAdapter,
)


def get_photo_storage() -> PhotoStoragePort:
    return ScalewayPhotoStorageAdapter(get_settings().require_photo_storage())
