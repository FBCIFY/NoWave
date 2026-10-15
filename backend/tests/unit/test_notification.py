from datetime import UTC, datetime, timedelta
import json
from pathlib import Path
from uuid import UUID

import pytest

from app.domain.notification import coordinate_dms, next_attempt_at, parse_retry_after
from backend.tests.notification_helpers import delivery


NOW = datetime(2026, 10, 13, 12, tzinfo=UTC)


@pytest.mark.parametrize(
    "attempt,minutes", [(0, 1), (1, 5), (2, 15), (3, 30), (4, 60), (15, 60)]
)
def test_retry_schedule(attempt, minutes):
    assert next_attempt_at(attempt, NOW) == NOW + timedelta(minutes=minutes)


@pytest.mark.parametrize(
    "value,seconds", [("120", 120), ("Tue, 13 Oct 2026 12:05:00 GMT", 300)]
)
def test_retry_after_seconds_and_date(value, seconds):
    assert parse_retry_after(value, NOW) == NOW + timedelta(seconds=seconds)


@pytest.mark.parametrize(
    "value", [None, "bad", "-1", "NaN", "9" * 500, "Mon, 12 Oct 2026 12:05:00 GMT"]
)
def test_unusable_retry_after_is_ignored(value):
    assert parse_retry_after(value, NOW) is None


def test_retry_after_can_extend_but_not_shorten_delay():
    assert next_attempt_at(1, NOW, NOW + timedelta(seconds=30)) == NOW + timedelta(
        minutes=5
    )
    assert next_attempt_at(4, NOW, NOW + timedelta(hours=2)) == NOW + timedelta(hours=2)


@pytest.mark.parametrize(
    "value,expected",
    [(12.9999, "13° 0′ 0″ N"), (-43.31, "43° 18′ 36″ S"), (0, "0° 0′ 0″ N")],
)
def test_dms_matches_mobile_rounding(value, expected):
    assert coordinate_dms(value, "N", "S") == expected


def test_payload_uses_history_identity_and_only_strings():
    message = delivery()
    data = message.data()
    assert data["alert_id"] == str(message.alert_id)
    assert data["notification_id"] == str(message.notification_id)
    assert data["position_dms"] == "43° 18′ 36″ N · 5° 24′ 0″ E"
    assert all(isinstance(value, str) for value in data.values())
    assert message.fcm_token not in repr(message)


def test_serialization_matches_the_fixture_read_by_flutter():
    fixture = json.loads(
        (Path(__file__).parents[1] / "fixtures/alert_push.json").read_text()
    )
    message = delivery(
        notification_id=UUID(fixture["notification_id"]),
        alert_id=UUID(fixture["alert_id"]),
        report_id=UUID(fixture["report_id"]),
        alerted_at=NOW,
        expires_at=NOW + timedelta(days=1),
    )
    assert message.data() == fixture
