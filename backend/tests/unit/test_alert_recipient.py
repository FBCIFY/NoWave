from uuid import uuid4

import pytest

from app.domain.alert_recipient import ALERT_RADIUS_M, AlertRecipient, RecipientDevice


def test_recipient_keeps_all_devices_and_uses_nearest_distance():
    farther = RecipientDevice(uuid4(), "farther-token", 5_000)
    nearer = RecipientDevice(uuid4(), "nearer-token", 2_000)

    recipient = AlertRecipient(user_id=uuid4(), devices=(farther, nearer))

    assert recipient.distance_m == 2_000
    assert recipient.devices == (farther, nearer)


@pytest.mark.parametrize("distance_m", [0, ALERT_RADIUS_M])
def test_distance_boundaries_are_included(distance_m):
    device = RecipientDevice(uuid4(), "token", distance_m)

    assert device.distance_m == distance_m


@pytest.mark.parametrize("distance_m", [-1, 18_520.01, float("nan"), float("inf")])
def test_invalid_or_out_of_range_distance_is_rejected(distance_m):
    with pytest.raises(ValueError, match="device distance"):
        RecipientDevice(uuid4(), "token", distance_m)


@pytest.mark.parametrize("token", ["", "   "])
def test_blank_token_is_rejected(token):
    with pytest.raises(ValueError, match="fcm_token"):
        RecipientDevice(uuid4(), token, 1_000)


def test_recipient_without_devices_is_rejected():
    with pytest.raises(ValueError, match="at least one"):
        AlertRecipient(user_id=uuid4(), devices=())


def test_duplicate_device_id_is_rejected_even_with_different_data():
    device_id = uuid4()
    first = RecipientDevice(device_id, "first-token", 1_000)
    second = RecipientDevice(device_id, "second-token", 2_000)

    with pytest.raises(ValueError, match="distinct"):
        AlertRecipient(user_id=uuid4(), devices=(first, second))
