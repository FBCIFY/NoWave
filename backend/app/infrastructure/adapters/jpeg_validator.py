from io import BytesIO
import warnings

from PIL import Image, UnidentifiedImageError

from app.application.ports.image_validator import ImageValidator, ValidatedImage
from app.domain.errors import InvalidPhotoError

MAX_PHOTO_BYTES = 500_000


class JpegValidator(ImageValidator):
    """Keep the original bytes, but accept only decodable JPEGs without EXIF."""

    def validate(
        self, content: bytes, declared_mime_type: str | None = None
    ) -> ValidatedImage:
        if not 1 <= len(content) <= MAX_PHOTO_BYTES:
            raise InvalidPhotoError("photo size must be between 1 and 500000 bytes")
        if declared_mime_type != "image/jpeg":
            raise InvalidPhotoError("photo content type must be image/jpeg")
        if not content.endswith(b"\xff\xd9"):
            raise InvalidPhotoError("photo must be a complete JPEG")

        try:
            with warnings.catch_warnings():
                warnings.simplefilter("error", Image.DecompressionBombWarning)
                with Image.open(BytesIO(content), formats=("JPEG",)) as image:
                    if "exif" in image.info:
                        raise InvalidPhotoError("photo must not contain EXIF metadata")
                    image.load()
        except (
            UnidentifiedImageError,
            OSError,
            ValueError,
            Image.DecompressionBombError,
            Image.DecompressionBombWarning,
        ) as exc:
            raise InvalidPhotoError("photo must be a decodable JPEG") from exc

        return ValidatedImage(
            content=content, mime_type="image/jpeg", size_bytes=len(content)
        )
