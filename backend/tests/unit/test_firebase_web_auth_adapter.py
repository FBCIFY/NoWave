import json
from datetime import timedelta

import firebase_admin
import httpx
import pytest
from firebase_admin import auth
from firebase_admin.exceptions import FirebaseError

from app.config.settings import ConfigurationError
from app.domain.errors import (
    InvalidCredentialsError,
    InvalidSessionError,
    SignInUnavailableError,
)
from app.infrastructure.adapters.firebase_web_auth_adapter import (
    CLOCK_SKEW_SECONDS,
    SIGN_IN_URL,
    FirebaseWebAuthAdapter,
)


API_KEY = "web-api-key-test"


def adapter_answering(status_code=200, body=None, requests=None):
    def handler(request):
        if requests is not None:
            requests.append(request)
        return httpx.Response(status_code, json=body)

    return FirebaseWebAuthAdapter(
        API_KEY,
        http_client=httpx.Client(transport=httpx.MockTransport(handler)),
    )


def firebase_error(message):
    return {"error": {"code": 400, "message": message}}


def test_sign_in_returns_id_token():
    requests = []
    adapter = adapter_answering(body={"idToken": "id-token"}, requests=requests)

    assert adapter.sign_in_with_password("a@nowave.test", "secret") == "id-token"

    request = requests[0]
    assert str(request.url).startswith(SIGN_IN_URL)
    assert request.url.params["key"] == API_KEY
    assert json.loads(request.read()) == {
        "email": "a@nowave.test",
        "password": "secret",
        "returnSecureToken": True,
    }


@pytest.mark.parametrize(
    "message",
    [
        "INVALID_LOGIN_CREDENTIALS",
        "EMAIL_NOT_FOUND",
        "INVALID_PASSWORD",
        "USER_DISABLED",
        "INVALID_EMAIL",
        "MISSING_PASSWORD",
    ],
)
def test_sign_in_maps_credential_errors(message):
    adapter = adapter_answering(400, firebase_error(message))

    with pytest.raises(InvalidCredentialsError):
        adapter.sign_in_with_password("a@nowave.test", "wrong")


@pytest.mark.parametrize(
    ("status_code", "body"),
    [
        (
            400,
            firebase_error(
                "TOO_MANY_ATTEMPTS_TRY_LATER : Access to this account "
                "has been temporarily disabled"
            ),
        ),
        (400, firebase_error("API key not valid. Please pass a valid API key.")),
        (500, None),
        (400, {"unexpected": True}),
        (200, {"unexpected": True}),
    ],
)
def test_sign_in_maps_other_errors_to_unavailable(status_code, body):
    adapter = adapter_answering(status_code, body)

    with pytest.raises(SignInUnavailableError):
        adapter.sign_in_with_password("a@nowave.test", "secret")


def test_network_error_does_not_leak_api_key():
    def handler(request):
        raise httpx.ConnectError(f"cannot reach {request.url}")

    adapter = FirebaseWebAuthAdapter(
        API_KEY,
        http_client=httpx.Client(transport=httpx.MockTransport(handler)),
    )

    with pytest.raises(SignInUnavailableError) as error:
        adapter.sign_in_with_password("a@nowave.test", "secret")

    assert API_KEY not in str(error.value)
    assert error.value.__cause__ is None
    assert error.value.__suppress_context__


@pytest.mark.parametrize("api_key", [None, "", "  "])
def test_sign_in_requires_api_key(api_key):
    adapter = FirebaseWebAuthAdapter(api_key)

    with pytest.raises(ConfigurationError):
        adapter.sign_in_with_password("a@nowave.test", "secret")


@pytest.fixture
def firebase_app(monkeypatch):
    monkeypatch.setattr(firebase_admin, "get_app", lambda: object())


def test_session_cookie_is_checked_for_revocation(monkeypatch, firebase_app):
    calls = []

    def verify(cookie, check_revoked, clock_skew_seconds):
        calls.append((cookie, check_revoked, clock_skew_seconds))
        return {"uid": "firebase-admin-1"}

    monkeypatch.setattr(auth, "verify_session_cookie", verify)

    identity = FirebaseWebAuthAdapter(None).verify_session_cookie("cookie")

    assert identity == {"uid": "firebase-admin-1"}
    assert calls == [("cookie", True, CLOCK_SKEW_SECONDS)]


@pytest.mark.parametrize(
    "error",
    [
        ValueError("empty cookie"),
        auth.InvalidSessionCookieError("bad cookie"),
        auth.ExpiredSessionCookieError("expired", cause=None),
        auth.RevokedSessionCookieError("revoked"),
        auth.UserDisabledError("disabled"),
    ],
)
def test_invalid_session_cookie(monkeypatch, firebase_app, error):
    def verify(cookie, check_revoked, clock_skew_seconds):
        raise error

    monkeypatch.setattr(auth, "verify_session_cookie", verify)

    with pytest.raises(InvalidSessionError):
        FirebaseWebAuthAdapter(None).verify_session_cookie("cookie")


def test_session_check_outage_is_unavailable(monkeypatch, firebase_app):
    def verify(cookie, check_revoked, clock_skew_seconds):
        raise auth.CertificateFetchError("no certificates", cause=None)

    monkeypatch.setattr(auth, "verify_session_cookie", verify)

    with pytest.raises(SignInUnavailableError):
        FirebaseWebAuthAdapter(None).verify_session_cookie("cookie")


def test_create_session_cookie(monkeypatch, firebase_app):
    calls = []

    def create(id_token, expires_in):
        calls.append((id_token, expires_in))
        return "session-cookie"

    monkeypatch.setattr(auth, "create_session_cookie", create)

    cookie = FirebaseWebAuthAdapter(None).create_session_cookie(
        "id-token",
        timedelta(hours=8),
    )

    assert cookie == "session-cookie"
    assert calls == [("id-token", timedelta(hours=8))]


def test_create_session_cookie_failure_is_unavailable(monkeypatch, firebase_app):
    def create(id_token, expires_in):
        raise FirebaseError("UNAVAILABLE", "outage")

    monkeypatch.setattr(auth, "create_session_cookie", create)

    with pytest.raises(SignInUnavailableError):
        FirebaseWebAuthAdapter(None).create_session_cookie(
            "id-token",
            timedelta(hours=8),
        )


def test_verify_id_token_tolerates_clock_skew(monkeypatch, firebase_app):
    calls = []

    def verify(id_token, clock_skew_seconds):
        calls.append((id_token, clock_skew_seconds))
        return {"uid": "firebase-admin-1"}

    monkeypatch.setattr(auth, "verify_id_token", verify)

    FirebaseWebAuthAdapter(None).verify_id_token("id-token")

    assert calls == [("id-token", CLOCK_SKEW_SECONDS)]


@pytest.mark.parametrize(
    "error",
    [
        ValueError("token from another project"),
        auth.InvalidIdTokenError("bad token"),
    ],
)
def test_rejected_fresh_id_token_is_a_setup_problem(
    monkeypatch,
    firebase_app,
    error,
):
    def verify(id_token, clock_skew_seconds):
        raise error

    monkeypatch.setattr(auth, "verify_id_token", verify)

    with pytest.raises(SignInUnavailableError):
        FirebaseWebAuthAdapter(None).verify_id_token("id-token")
