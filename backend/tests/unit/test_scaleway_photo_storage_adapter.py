from datetime import UTC, datetime, timedelta
from urllib.parse import parse_qs, urlparse

from botocore.stub import Stubber
import pytest

from app.config.settings import PhotoStorageSettings
from app.domain.errors import PhotoStorageError
from app.infrastructure.adapters.scaleway_photo_storage_adapter import (
    ScalewayPhotoStorageAdapter,
)


@pytest.fixture
def storage():
    return ScalewayPhotoStorageAdapter(
        PhotoStorageSettings("photos-test", "fr-par", "test-key", "test-secret")
    )


def test_private_upload_and_idempotent_delete(storage):
    with Stubber(storage.client) as stub:
        stub.add_response(
            "put_object",
            {},
            {
                "Bucket": "photos-test",
                "Key": "reports/photo.jpg",
                "Body": b"jpeg",
                "ContentType": "image/jpeg",
                "ACL": "private",
            },
        )
        stub.add_response(
            "delete_object", {}, {"Bucket": "photos-test", "Key": "reports/photo.jpg"}
        )
        storage.store("reports/photo.jpg", b"jpeg", "image/jpeg")
        storage.delete("reports/photo.jpg")
        stub.assert_no_pending_responses()


def test_signed_url_uses_scaleway_and_five_minute_sigv4(storage):
    url = storage.create_read_url("reports/photo.jpg", timedelta(minutes=5))
    parsed = urlparse(url)
    query = parse_qs(parsed.query)
    assert parsed.scheme == "https"
    assert parsed.hostname.endswith("scw.cloud")
    assert query["X-Amz-Expires"] == ["300"]
    assert query["X-Amz-Algorithm"] == ["AWS4-HMAC-SHA256"]
    assert "fr-par/s3/aws4_request" in query["X-Amz-Credential"][0]


def test_listing_follows_all_pages(storage):
    timestamp = datetime.now(UTC)
    with Stubber(storage.client) as stub:
        stub.add_response(
            "list_objects_v2",
            {
                "IsTruncated": True,
                "NextContinuationToken": "next",
                "Contents": [{"Key": "reports/first.jpg", "LastModified": timestamp}],
            },
            {"Bucket": "photos-test", "Prefix": "reports/"},
        )
        stub.add_response(
            "list_objects_v2",
            {
                "IsTruncated": False,
                "Contents": [{"Key": "reports/second.jpg", "LastModified": timestamp}],
            },
            {
                "Bucket": "photos-test",
                "Prefix": "reports/",
                "ContinuationToken": "next",
            },
        )
        assert [p.object_key for p in storage.list_photos()] == [
            "reports/first.jpg",
            "reports/second.jpg",
        ]


@pytest.mark.parametrize(
    "operation", ["put_object", "delete_object", "list_objects_v2"]
)
def test_storage_errors_are_translated_without_exposing_sdk_details(storage, operation):
    with Stubber(storage.client) as stub:
        stub.add_client_error(
            operation,
            service_error_code="ServiceUnavailable",
            service_message="private SDK details",
            http_status_code=503,
        )
        with pytest.raises(PhotoStorageError) as error:
            if operation == "put_object":
                storage.store("reports/photo.jpg", b"jpeg", "image/jpeg")
            elif operation == "delete_object":
                storage.delete("reports/photo.jpg")
            else:
                list(storage.list_photos())
        assert "private" not in str(error.value)
