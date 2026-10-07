from app.api.schemas.report import (
    ReportPhotoResponse,
    ReportResponse,
)
from app.api.schemas.report_detail import (
    ReportDetailPhotoResponse,
    ReportDetailResponse,
)


EXPECTED_SHARED_FIELDS = {
    "id",
    "version",
    "category",
    "description",
    "positioning_mode",
    "final_position",
    "status",
    "observed_at",
    "expires_at",
    "photo",
}

EXPECTED_POST_ONLY_FIELDS = {
    "author_id",
    "client_report_id",
    "created_at",
    "updated_at",
}

EXPECTED_DETAIL_ONLY_FIELDS = {
    "author",
    "boat",
}


def test_report_response_and_detail_contracts_are_aligned():
    post_fields = set(
        ReportResponse.model_fields
    )

    detail_fields = set(
        ReportDetailResponse.model_fields
    )

    assert (
        post_fields & detail_fields
        == EXPECTED_SHARED_FIELDS
    )

    assert (
        post_fields - detail_fields
        == EXPECTED_POST_ONLY_FIELDS
    )

    assert (
        detail_fields - post_fields
        == EXPECTED_DETAIL_ONLY_FIELDS
    )


def test_photo_contract_is_consistent():
    assert set(
        ReportPhotoResponse.model_fields
    ) == {
        "status",
        "url",
    }

    assert set(
        ReportDetailPhotoResponse.model_fields
    ) == {
        "status",
        "url",
    }
