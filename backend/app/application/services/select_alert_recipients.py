from uuid import UUID

from app.application.ports.alert_recipient_repository import AlertRecipientRepository
from app.domain.alert_recipient import AlertRecipient


class SelectAlertRecipients:
    """Shared entry point for report publication and the alert worker."""

    def __init__(self, recipient_repository: AlertRecipientRepository):
        self.recipient_repository = recipient_repository

    def execute(self, report_id: UUID) -> tuple[AlertRecipient, ...]:
        return self.recipient_repository.select_for_report(report_id)
