from uuid import uuid4

import pytest

from app.application.ports.alert_recipient_repository import AlertRecipientRepository
from app.application.services.select_alert_recipients import SelectAlertRecipients
from app.domain.alert_recipient import AlertRecipient, RecipientDevice
from app.domain.errors import ReportNotFoundError


class FakeAlertRecipientRepository(AlertRecipientRepository):
    """Prepared selections for consumer tests; does not simulate PostGIS."""

    def __init__(self, selections):
        self.selections = selections

    def select_for_report(self, report_id):
        if report_id not in self.selections:
            raise ReportNotFoundError("report not found")
        return self.selections[report_id]


def test_consumer_can_read_multiple_devices_from_the_shared_contract():
    report_id = uuid4()
    first_device = RecipientDevice(uuid4(), "first-token", 5_000)
    second_device = RecipientDevice(uuid4(), "second-token", 2_000)
    recipient = AlertRecipient(uuid4(), (first_device, second_device))
    repository = FakeAlertRecipientRepository({report_id: (recipient,)})

    recipients = SelectAlertRecipients(repository).execute(report_id)

    assert len(recipients) == 1
    assert recipients[0].user_id == recipient.user_id
    assert recipients[0].distance_m == 2_000
    assert {device.device_id for device in recipients[0].devices} == {
        first_device.device_id,
        second_device.device_id,
    }


def test_no_recipients_returns_an_empty_tuple():
    report_id = uuid4()
    repository = FakeAlertRecipientRepository({report_id: ()})

    assert SelectAlertRecipients(repository).execute(report_id) == ()


def test_missing_report_is_distinct_from_no_recipients():
    repository = FakeAlertRecipientRepository({})

    with pytest.raises(ReportNotFoundError):
        SelectAlertRecipients(repository).execute(uuid4())
