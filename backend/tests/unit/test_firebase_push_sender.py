from datetime import UTC, datetime, timedelta
import json
from types import SimpleNamespace

from google.auth.exceptions import RefreshError
import httpx
import pytest

from app.domain.notification import PushSendError
from app.infrastructure.adapters.firebase_push_sender import FirebasePushSender
from backend.tests.notification_helpers import delivery


def sender_with_response(status, body, headers=None):
    requests = []

    def handle(request):
        requests.append(request)
        return httpx.Response(status, json=body, headers=headers)

    sender = FirebasePushSender(
        SimpleNamespace(valid=True, token="access-token"),
        "test-project",
        client=httpx.Client(transport=httpx.MockTransport(handle)),
    )
    return sender, requests


def test_acceptance_payload_and_expiration():
    sender, requests = sender_with_response(200, {"name": "projects/test/messages/1"})
    now = datetime.now(UTC)
    message = delivery(
        expires_at=now + timedelta(seconds=120), description="Filet dérivant"
    )
    try:
        assert sender.send(message, now) == "projects/test/messages/1"
        payload = json.loads(requests[0].content)["message"]
        assert payload["data"] == message.data()
        assert payload["notification"] == {
            "title": "Pollution · 0,5 NM",
            "body": "« Filet dérivant »",
        }
        assert payload["android"]["ttl"] == "120s"
        assert payload["apns"]["headers"]["apns-expiration"] == str(
            int(message.expires_at.timestamp())
        )
        assert requests[0].headers["Authorization"] == "Bearer access-token"
    finally:
        sender.close()


@pytest.mark.parametrize(
    "status,code,permanent,invalid",
    [
        (429, "QUOTA_EXCEEDED", False, False),
        (503, "UNAVAILABLE", False, False),
        (500, "INTERNAL", False, False),
        (401, "UNAUTHENTICATED", False, False),
        (403, "PERMISSION_DENIED", False, False),
        (408, "DEADLINE_EXCEEDED", False, False),
        (404, "UNREGISTERED", True, True),
        (403, "SENDER_ID_MISMATCH", True, False),
        (400, "INVALID_ARGUMENT", True, False),
    ],
)
def test_error_classification_never_retries_inside_adapter(
    status, code, permanent, invalid
):
    body = {
        "error": {
            "details": [
                {
                    "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
                    "errorCode": code,
                }
            ]
        }
    }
    sender, requests = sender_with_response(status, body, {"Retry-After": "7200"})
    try:
        with pytest.raises(PushSendError) as caught:
            sender.send(delivery(), datetime.now(UTC))
        assert caught.value.permanent is permanent
        assert caught.value.invalid_token is invalid
        assert len(requests) == 1
        if not permanent:
            assert caught.value.retry_after > datetime.now(UTC) + timedelta(minutes=119)
    finally:
        sender.close()


def test_expired_message_never_reaches_fcm():
    sender, requests = sender_with_response(200, {"name": "unexpected"})
    now = datetime.now(UTC)
    try:
        with pytest.raises(PushSendError, match="report_expired"):
            sender.send(delivery(expires_at=now), now)
        assert requests == []
    finally:
        sender.close()


@pytest.mark.parametrize("body", [{}, [], {"name": ""}])
def test_malformed_success_is_not_recorded_as_accepted(body):
    sender, _ = sender_with_response(200, body)
    try:
        with pytest.raises(PushSendError, match="fcm_invalid_response"):
            sender.send(delivery(), datetime.now(UTC))
    finally:
        sender.close()


def test_network_error_is_temporary_and_does_not_expose_token():
    calls = []

    def timeout(request):
        calls.append(request)
        raise httpx.ReadTimeout("secret-token", request=request)

    sender = FirebasePushSender(
        SimpleNamespace(token="secret-token"),
        "project",
        client=httpx.Client(transport=httpx.MockTransport(timeout)),
    )
    try:
        with pytest.raises(PushSendError, match="^fcm_network$"):
            sender.send(delivery(), datetime.now(UTC))
        assert len(calls) == 1
    finally:
        sender.close()


def test_credential_refresh_failure_is_sanitized():
    def refresh(request):
        raise RefreshError("private credential details")

    sender, requests = sender_with_response(200, {})
    sender.credentials = SimpleNamespace(valid=False, refresh=refresh)
    try:
        with pytest.raises(PushSendError, match="^fcm_authentication$"):
            sender.prepare()
        assert requests == []
    finally:
        sender.close()


def test_unauthorized_response_refreshes_credentials_on_next_attempt():
    sender, requests = sender_with_response(401, {})
    refreshes = []
    sender.credentials = SimpleNamespace(
        valid=True, token="old", refresh=lambda request: refreshes.append(request)
    )
    try:
        with pytest.raises(PushSendError):
            sender.send(delivery(), datetime.now(UTC))
        assert refreshes == []
        sender.prepare()
        assert len(refreshes) == 1
        assert len(requests) == 1
    finally:
        sender.close()
