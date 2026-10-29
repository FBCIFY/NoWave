from io import BytesIO
from threading import BoundedSemaphore
import warnings

from PIL import Image, UnidentifiedImageError

from app.application.ports.image_validator import (
    ImageValidator,
    ValidatedImage,
)
from app.domain.errors import InvalidPhotoError


MAX_PHOTO_BYTES = 500_000

# Flutter prepareReportJpeg() réduit le côté le plus long à 1600 px.
MAX_PHOTO_WIDTH = 1_600
MAX_PHOTO_HEIGHT = 1_600
MAX_PHOTO_PIXELS = 2_560_000

# Le décodage est exécuté dans le thread pool FastAPI.
# On borne explicitement le nombre de rasters présents simultanément.
MAX_CONCURRENT_JPEG_DECODES = 4
_JPEG_DECODE_SLOTS = BoundedSemaphore(
    MAX_CONCURRENT_JPEG_DECODES
)


class JpegValidator(ImageValidator):
    """Validate bounded JPEGs without changing the original bytes."""

    def validate(
        self,
        content: bytes,
        declared_mime_type: str | None = None,
    ) -> ValidatedImage:
        if not 1 <= len(content) <= MAX_PHOTO_BYTES:
            raise InvalidPhotoError(
                "photo size must be between 1 and 500000 bytes"
            )

        if declared_mime_type != "image/jpeg":
            raise InvalidPhotoError(
                "photo content type must be image/jpeg"
            )

        if not content.endswith(b"\xff\xd9"):
            raise InvalidPhotoError(
                "photo must be a complete JPEG"
            )

        try:
            with warnings.catch_warnings():
                warnings.simplefilter(
                    "error",
                    Image.DecompressionBombWarning,
                )

                with Image.open(
                    BytesIO(content),
                    formats=("JPEG",),
                ) as image:
                    width, height = image.size
                    pixel_count = width * height

                    if (
                        pixel_count > MAX_PHOTO_PIXELS
                        or width > MAX_PHOTO_WIDTH
                        or height > MAX_PHOTO_HEIGHT
                    ):
                        raise InvalidPhotoError(
                            "photo dimensions must be at most "
                            "1600x1600 and 2560000 pixels"
                        )

                    if "exif" in image.info:
                        raise InvalidPhotoError(
                            "photo must not contain EXIF metadata"
                        )

                    with _JPEG_DECODE_SLOTS:
                        image.load()

        except (
            UnidentifiedImageError,
            OSError,
            ValueError,
            Image.DecompressionBombError,
            Image.DecompressionBombWarning,
        ) as exc:
            raise InvalidPhotoError(
                "photo must be a decodable JPEG"
            ) from exc

        return ValidatedImage(
            content=content,
            mime_type="image/jpeg",
            size_bytes=len(content),
        )
