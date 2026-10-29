from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest

from backend.tools.send_test_notification import delivery_for, validate_target


NOW = datetime(2026, 10, 20, 14, tzinfo=UTC)


@pytest.fixture
def target():
    return dict(
        user_id=uuid4(), author_id=uuid4(), user_status="active",
        notifications_enabled=True, is_active=True, fcm_token="private-token",
        report_status="active", expires_at=NOW + timedelta(hours=1),
        measured_at=NOW, device_id=uuid4(), report_id=uuid4(),
        report_version=2, category="pollution", longitude=5.4, latitude=43.3,
        distance_m=100.0, description="Test réel", firebase_uid="recipient",
    )


def test_self_report_requires_explicit_override(target):
    target["author_id"] = target["user_id"]
    with pytest.raises(ValueError, match="allow-own-report"):
        validate_target(target, NOW)
    validate_target(target, NOW, allow_own_report=True)


@pytest.mark.parametrize("change", [
    {"user_status": "suspended"}, {"notifications_enabled": False},
    {"is_active": False}, {"fcm_token": None}, {"report_status": "removed"},
    {"expires_at": NOW}, {"measured_at": NOW - timedelta(minutes=6)},
    {"measured_at": NOW + timedelta(minutes=6)},
])
def test_test_mode_does_not_bypass_consent_or_availability(target, change):
    target.update(change)
    with pytest.raises(ValueError):
        validate_target(target, NOW, allow_own_report=True)


def test_missing_or_foreign_installation_is_rejected():
    with pytest.raises(ValueError, match="not found"):
        validate_target(None, NOW)


def test_real_payload_targets_the_selected_account_and_hides_tokens(target):
    validate_target(target, NOW)
    delivery = delivery_for(target, NOW)
    assert delivery.data()["report_id"] == str(target["report_id"])
    assert delivery.data()["report_version"] == "2"
    assert delivery.data()["recipient_firebase_uid"] == "recipient"
    assert "private-token" not in repr(delivery)
    assert delivery.description == "Test réel"
