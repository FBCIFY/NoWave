from datetime import UTC, datetime

import firebase_admin
from google.auth.exceptions import GoogleAuthError
from google.auth.transport.requests import Request
import httpx
import requests

from app.application.ports.push_sender import PushSender
from app.domain.notification import (
    NotificationDelivery,
    PushSendError,
    parse_retry_after,
)


class FirebasePushSender(PushSender):
    def __init__(self, credentials, project_id, client=None):
        self.credentials = credentials
        self.project_id = project_id
        self.client = client or httpx.Client(
            timeout=httpx.Timeout(10, connect=3),
            transport=httpx.HTTPTransport(retries=0),
        )
        self.auth_session = requests.Session()
        self.auth_request = Request(session=self.auth_session)
        self.refresh_required = False

    @classmethod
    def from_environment(cls):
        try:
            try:
                app = firebase_admin.get_app()
            except ValueError:
                app = firebase_admin.initialize_app()
            credentials = app.credential.get_credential()
            if not app.project_id:
                raise ValueError("missing project")
            return cls(credentials, app.project_id)
        except (ValueError, OSError, GoogleAuthError):
            raise PushSendError("fcm_configuration") from None

    def prepare(self) -> None:
        try:
            if self.refresh_required or not self.credentials.valid:
                self.credentials.refresh(self._auth_request)
                self.refresh_required = False
        except (GoogleAuthError, requests.RequestException, ValueError):
            raise PushSendError("fcm_authentication") from None

    def _auth_request(self, *args, **kwargs):
        kwargs["timeout"] = 10
        return self.auth_request(*args, **kwargs)

    def send(self, delivery: NotificationDelivery, now: datetime) -> str:
        remaining = (delivery.expires_at - now).total_seconds()
        if remaining <= 0:
            raise PushSendError("report_expired", permanent=True)
        message = {
            "token": delivery.fcm_token,
            "data": delivery.data(),
            "notification": {
                "title": "Alerte NoWave",
                "body": "Un signalement à proximité.",
            },
            "android": {
                "ttl": f"{int(remaining)}s",
                "notification": {"tag": str(delivery.alert_id)},
            },
            "apns": {
                "headers": {
                    "apns-expiration": str(int(delivery.expires_at.timestamp())),
                    "apns-collapse-id": str(delivery.alert_id),
                },
            },
        }
        try:
            response = self.client.post(
                f"https://fcm.googleapis.com/v1/projects/{self.project_id}/messages:send",
                headers={"Authorization": f"Bearer {self.credentials.token}"},
                json={"message": message},
            )
        except httpx.RequestError:
            raise PushSendError("fcm_network") from None
        try:
            body = response.json()
        except ValueError:
            body = {}
        if not isinstance(body, dict):
            body = {}
        if response.is_success:
            name = body.get("name")
            if not isinstance(name, str) or not name:
                raise PushSendError("fcm_invalid_response")
            return name

        retry_after = parse_retry_after(
            response.headers.get("Retry-After"), datetime.now(UTC)
        )
        error = body.get("error", {})
        details = error.get("details", []) if isinstance(error, dict) else []
        fcm_code = None
        if isinstance(details, list):
            for detail in details:
                if (
                    isinstance(detail, dict)
                    and detail.get("@type")
                    == "type.googleapis.com/google.firebase.fcm.v1.FcmError"
                ):
                    fcm_code = detail.get("errorCode")
                    break
        if fcm_code == "UNREGISTERED":
            raise PushSendError("fcm_unregistered", permanent=True, invalid_token=True)
        if fcm_code == "SENDER_ID_MISMATCH":
            raise PushSendError("fcm_sender_mismatch", permanent=True)
        if response.status_code in (401, 403) or fcm_code == "THIRD_PARTY_AUTH_ERROR":
            self.refresh_required = (
                response.status_code == 401 and fcm_code != "THIRD_PARTY_AUTH_ERROR"
            )
            raise PushSendError("fcm_authentication", retry_after=retry_after)
        if response.status_code == 429 or response.status_code >= 500:
            raise PushSendError("fcm_unavailable", retry_after=retry_after)
        if response.status_code == 408:
            raise PushSendError("fcm_timeout", retry_after=retry_after)
        raise PushSendError("fcm_invalid_request", permanent=True)

    def close(self):
        self.client.close()
        self.auth_session.close()
