import pytest

from app.domain.errors import InvalidPhotoError
from app.infrastructure.adapters.jpeg_validator import JpegValidator
from tests.photo_helpers import jpeg_bytes


@pytest.mark.parametrize("size", [None, 500_000])
def test_accepts_decodable_jpeg_without_changing_bytes(size):
    content = jpeg_bytes(size=size)
    result = JpegValidator().validate(content, "image/jpeg")
    assert result.content == content
    assert result.size_bytes == len(content)


@pytest.mark.parametrize(
    "content,mime",
    [
        (b"", "image/jpeg"),
        (b"x", "image/jpeg"),
        (b"\xff\xd8\xffnot-an-image\xff\xd9", "image/jpeg"),
        (jpeg_bytes()[:-20] + b"\xff\xd9", "image/jpeg"),
        (jpeg_bytes()[:-2], "image/jpeg"),
        (jpeg_bytes(exif=True), "image/jpeg"),
        (jpeg_bytes(size=500_001), "image/jpeg"),
        (jpeg_bytes(), "image/png"),
        (jpeg_bytes(), None),
    ],
)
def test_rejects_invalid_jpeg(content, mime):
    with pytest.raises(InvalidPhotoError):
        JpegValidator().validate(content, mime)
