from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.api.schemas.device import DeviceRegisterRequest


def test_register_device_rejects_whitespace_fcm_token():
    with pytest.raises(ValidationError):
        DeviceRegisterRequest(
            installation_id=uuid4(),
            platform="android",
            fcm_token="   ",
        )


def test_register_device_trims_fcm_token():
    request = DeviceRegisterRequest(
        installation_id=uuid4(),
        platform="android",
        fcm_token="  valid-fcm-token  ",
    )

    assert request.fcm_token == "valid-fcm-token"
