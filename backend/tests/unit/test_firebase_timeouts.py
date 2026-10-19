"""NW-202: inspect real SDK wiring and exercise stalled local HTTP transports."""

from contextlib import contextmanager
from datetime import UTC, datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread
from time import monotonic, sleep
from types import SimpleNamespace

import firebase_admin
from firebase_admin import _auth_client, credentials
from google.auth.credentials import AnonymousCredentials
from google.auth.exceptions import TransportError
import httpx
import pytest
import requests

from app.domain.notification import PushSendError
from app.infrastructure.adapters.firebase_push_sender import FirebasePushSender
from app.infrastructure.adapters.firebase_web_auth_adapter import FirebaseWebAuthAdapter
from backend.tests.notification_helpers import delivery


class TestCredentials(credentials.Base):
    __test__ = False

    def get_credential(self):
        return AnonymousCredentials()


@pytest.mark.parametrize("configured,expected", [(None, 120), (5, 5)])
def test_sdk_certificate_and_identity_timeouts(configured, expected):
    options = {"projectId": "timeout-test"}
    if configured is not None:
        options["httpTimeout"] = configured
    app = firebase_admin.initialize_app(TestCredentials(), options, name="nw-202-test")
    try:
        client = _auth_client.Client(app)
        assert client._token_verifier.request.timeout_seconds == expected
        assert client._user_manager.http_client.timeout == expected
    finally:
        firebase_admin.delete_app(app)


@contextmanager
def stalled_once():
    class Handler(BaseHTTPRequestHandler):
        calls = 0

        def do_GET(self):
            type(self).calls += 1
            if type(self).calls == 1:
                sleep(0.15)
            body = b'{"name":"projects/test/messages/1"}'
            try:
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass  # Expected when the client has enforced its read timeout.

        def do_POST(self):
            self.rfile.read(int(self.headers.get("Content-Length", 0)))
            self.do_GET()

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}", Handler
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


def test_sdk_certificate_read_timeout_and_recovery():
    # Real SDK transport; shorten only the injected test budget.
    app = firebase_admin.initialize_app(
        TestCredentials(),
        {"projectId": "timeout-test", "httpTimeout": 0.03},
        name="nw-202-certificate",
    )
    request = _auth_client.Client(app)._token_verifier.request
    try:
        with stalled_once() as (url, handler):
            started = monotonic()
            with pytest.raises(TransportError):
                request(url)
            assert monotonic() - started < 1
            assert request(url).status == 200
            assert handler.calls == 2
    finally:
        request.session.close()
        firebase_admin.delete_app(app)


def test_fcm_production_transport_budgets_and_no_retries():
    sender = FirebasePushSender(SimpleNamespace(valid=True), "test")
    try:
        assert sender.client.timeout == httpx.Timeout(10, connect=3)
        assert sender.client._transport._pool._retries == 0
    finally:
        sender.close()


def test_fcm_stalled_read_is_retryable_and_recovers():
    # Route the real HTTP client to loopback without contacting Firebase.
    with stalled_once() as (url, handler):

        class LocalClient(httpx.Client):
            def post(self, remote_url, **kwargs):
                return super().post(url, **kwargs)

        sender = FirebasePushSender(
            SimpleNamespace(valid=True, token="test-token"),
            "test",
            client=LocalClient(timeout=0.03, trust_env=False),
        )
        try:
            with pytest.raises(PushSendError, match="^fcm_network$") as caught:
                sender.send(delivery(), datetime.now(UTC))
            assert not caught.value.permanent
            assert (
                sender.send(delivery(), datetime.now(UTC)) == "projects/test/messages/1"
            )
            assert handler.calls == 2
        finally:
            sender.close()


def test_oauth_refresh_budget_and_recovery():
    calls = []

    def refresh(request):
        request("https://oauth.invalid")

    def transport(*args, **kwargs):
        calls.append(kwargs["timeout"])
        if len(calls) == 1:
            raise requests.Timeout("private credential details")

    sender = FirebasePushSender(SimpleNamespace(valid=False, refresh=refresh), "test")
    sender.auth_request = transport
    try:
        with pytest.raises(PushSendError, match="^fcm_authentication$"):
            sender.prepare()
        sender.prepare()
        assert calls == [10, 10]
    finally:
        sender.close()


def test_admin_password_sign_in_budget():
    def handle(request):
        assert request.extensions["timeout"] == dict.fromkeys(
            ["connect", "read", "write", "pool"], 5
        )
        return httpx.Response(200, json={"idToken": "test-token"})

    with httpx.Client(transport=httpx.MockTransport(handle)) as client:
        adapter = FirebaseWebAuthAdapter("test-key", http_client=client)
        assert (
            adapter.sign_in_with_password("admin@nowave.test", "test") == "test-token"
        )
