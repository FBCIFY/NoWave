from fastapi.testclient import TestClient
from app.main import app
from app.dependencies.admin_web_session import get_admin_web_session
from app.infrastructure.repositories.postgresql_admin_read_repository import PostgreSQLAdminReadRepository
from app.domain.user import User, UserRole


class Session:
    def authenticate(self, cookie):
        return User(firebase_uid='admin-test', username='admin', email='a@example.org', role=UserRole.ADMIN)


def test_map_read_requires_session_and_returns_real_coordinates(monkeypatch):
    client = TestClient(app, base_url='https://testserver')
    response = client.get('/admin/data/reports?west=-70&south=-20&east=20&north=60', follow_redirects=False)
    assert response.status_code == 303
    calls = []
    def fake_map(self, west, south, east, north, limit=1000):
        calls.append((west, south, east, north, limit))
        return [("11111111-1111-1111-1111-111111111111", -31.5, 42.25, 'object', 'active')], False
    monkeypatch.setattr(PostgreSQLAdminReadRepository, 'map_reports', fake_map)
    app.dependency_overrides[get_admin_web_session] = lambda: Session()
    client.cookies.set('__Host-nowave_admin_session', 'valid')
    try:
        response = client.get('/admin/data/reports?west=-70&south=-20&east=20&north=60')
        assert response.status_code == 200
        assert response.headers['cache-control'] == 'no-store'
        assert calls == [(-70, -20, 20, 60, 1000)]
        assert response.json()['features'][0]['geometry']['coordinates'] == [-31.5, 42.25]
        invalid = client.get('/admin/data/reports?west=20&south=0&east=-20&north=60')
        assert invalid.status_code == 422
    finally:
        app.dependency_overrides.clear()
