from concurrent.futures import ThreadPoolExecutor
from threading import Lock
import time

from PIL import JpegImagePlugin
import pytest

from app.domain.errors import InvalidPhotoError
from app.infrastructure.adapters.jpeg_validator import (
    JpegValidator,
    MAX_CONCURRENT_JPEG_DECODES,
    MAX_PHOTO_HEIGHT,
    MAX_PHOTO_PIXELS,
    MAX_PHOTO_WIDTH,
)
from tests.photo_helpers import (
    jpeg_bytes,
    jpeg_with_claimed_dimensions,
)


@pytest.mark.parametrize("size", [None, 500_000])
def test_accepts_decodable_jpeg_without_changing_bytes(size):
    content = jpeg_bytes(size=size)

    result = JpegValidator().validate(
        content,
        "image/jpeg",
    )

    assert result.content == content
    assert result.size_bytes == len(content)


def test_accepts_flutter_dimension_ceiling():
    content = jpeg_bytes(
        dimensions=(
            MAX_PHOTO_WIDTH,
            MAX_PHOTO_HEIGHT,
        )
    )

    result = JpegValidator().validate(
        content,
        "image/jpeg",
    )

    assert result.content == content
    assert (
        MAX_PHOTO_WIDTH * MAX_PHOTO_HEIGHT
        == MAX_PHOTO_PIXELS
    )


@pytest.mark.parametrize(
    "width,height",
    [
        (MAX_PHOTO_WIDTH + 1, 1),
        (1, MAX_PHOTO_HEIGHT + 1),
        (8_000, 8_000),
    ],
)
def test_rejects_oversized_dimensions_before_decode(
    monkeypatch,
    width,
    height,
):
    content = jpeg_with_claimed_dimensions(
        width,
        height,
    )

    load_called = False

    def fail_if_decoded(self, *args, **kwargs):
        nonlocal load_called
        load_called = True
        raise AssertionError(
            "raster decoding must not start"
        )

    monkeypatch.setattr(
        JpegImagePlugin.JpegImageFile,
        "load",
        fail_if_decoded,
    )

    with pytest.raises(
        InvalidPhotoError,
        match="photo dimensions",
    ):
        JpegValidator().validate(
            content,
            "image/jpeg",
        )

    assert load_called is False


def test_limits_concurrent_raster_decodes(
    monkeypatch,
):
    content = jpeg_bytes(
        dimensions=(256, 256)
    )

    original_load = (
        JpegImagePlugin.JpegImageFile.load
    )

    active_decodes = 0
    peak_decodes = 0
    lock = Lock()

    def tracked_load(self, *args, **kwargs):
        nonlocal active_decodes
        nonlocal peak_decodes

        with lock:
            active_decodes += 1
            peak_decodes = max(
                peak_decodes,
                active_decodes,
            )

        try:
            result = original_load(
                self,
                *args,
                **kwargs,
            )

            # Garde le raster vivant assez longtemps pour
            # permettre aux autres threads d'entrer.
            time.sleep(0.05)

            return result
        finally:
            with lock:
                active_decodes -= 1

    monkeypatch.setattr(
        JpegImagePlugin.JpegImageFile,
        "load",
        tracked_load,
    )

    validator = JpegValidator()

    def validate(_):
        return validator.validate(
            content,
            "image/jpeg",
        )

    workers = MAX_CONCURRENT_JPEG_DECODES * 3

    with ThreadPoolExecutor(
        max_workers=workers
    ) as executor:
        list(
            executor.map(
                validate,
                range(workers),
            )
        )

    assert (
        peak_decodes
        == MAX_CONCURRENT_JPEG_DECODES
    )


@pytest.mark.parametrize(
    "content,mime",
    [
        (b"", "image/jpeg"),
        (b"x", "image/jpeg"),
        (
            b"\xff\xd8\xffnot-an-image\xff\xd9",
            "image/jpeg",
        ),
        (
            jpeg_bytes()[:-20] + b"\xff\xd9",
            "image/jpeg",
        ),
        (
            jpeg_bytes()[:-2],
            "image/jpeg",
        ),
        (
            jpeg_bytes(exif=True),
            "image/jpeg",
        ),
        (
            jpeg_bytes(size=500_001),
            "image/jpeg",
        ),
        (
            jpeg_bytes(),
            "image/png",
        ),
        (
            jpeg_bytes(),
            None,
        ),
    ],
)
def test_rejects_invalid_jpeg(
    content,
    mime,
):
    with pytest.raises(InvalidPhotoError):
        JpegValidator().validate(
            content,
            mime,
        )
