from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.main import app
from app.domain.errors import ReportNotFoundError


client = TestClient(app)


@app.get("/test-report-not-found")
def trigger_report_not_found():
    raise ReportNotFoundError("Report not found")


def test_report_not_found_handler():
    response = client.get("/test-report-not-found")

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "report_not_found"
    assert response.json()["error"]["message"] == "Report not found"
    assert response.json()["error"]["details"] is None


@app.get("/test-authentication-required")
def trigger_authentication_required():
    raise HTTPException(
        status_code=401,
        detail="Authentication required",
    )


@app.get("/test-invalid-authentication-token")
def trigger_invalid_authentication_token():
    raise HTTPException(
        status_code=401,
        detail="Invalid authentication token",
    )


def test_authentication_required_handler():
    response = client.get("/test-authentication-required")

    assert response.status_code == 401
    assert response.json() == {
        "error": {
            "code": "authentication_required",
            "message": "Authentication required",
            "details": None,
        }
    }


def test_invalid_authentication_token_handler():
    response = client.get("/test-invalid-authentication-token")

    assert response.status_code == 401
    assert response.json() == {
        "error": {
            "code": "invalid_authentication_token",
            "message": "Invalid authentication token",
            "details": None,
        }
    }


def test_unknown_route_returns_normalized_404():
    response = client.get("/this-route-does-not-exist")

    assert response.status_code == 404
    assert response.json() == {
        "error": {
            "code": "http_404",
            "message": "Not Found",
            "details": None,
        }
    }
