from uuid import uuid4

import pytest

from app.domain.alert import ALERT_RADIUS_M, AlertRecipient


def test_alert_radius_is_ten_nautical_miles():
    assert ALERT_RADIUS_M == 10 * 1852


def test_alert_recipient_accepts_zero_distance():
    device_ids = (uuid4(), uuid4())

    recipient = AlertRecipient(
        user_id=uuid4(),
        distance_m=0,
        device_ids=device_ids,
    )

    assert recipient.device_ids == device_ids


@pytest.mark.parametrize(
    "distance_m",
    [-0.1, float("inf"), float("nan")],
)
def test_alert_recipient_rejects_invalid_distance(distance_m):
    with pytest.raises(ValueError):
        AlertRecipient(
            user_id=uuid4(),
            distance_m=distance_m,
            device_ids=(uuid4(),),
        )


def test_alert_recipient_needs_a_device():
    with pytest.raises(ValueError):
        AlertRecipient(
            user_id=uuid4(),
            distance_m=10,
            device_ids=(),
        )


def test_alert_recipient_rejects_duplicate_devices():
    device_id = uuid4()

    with pytest.raises(ValueError):
        AlertRecipient(
            user_id=uuid4(),
            distance_m=10,
            device_ids=(device_id, device_id),
        )
