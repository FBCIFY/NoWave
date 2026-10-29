from datetime import UTC, datetime
from uuid import UUID

import pytest
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


@pytest.fixture
def signed_client():
    app.dependency_overrides[get_admin_web_session] = lambda: Session()
    client = TestClient(app, base_url='https://testserver')
    client.cookies.set('__Host-nowave_admin_session', 'valid')
    yield client
    app.dependency_overrides.clear()


@pytest.mark.parametrize('count', [0, 1, 20, 21, 40, 41])
def test_user_report_pages_contract(signed_client, monkeypatch, count):
    ids = [str(UUID(int=i + 1)) for i in range(count)]
    user_id = UUID(int=100)
    calls = []

    def read(self, requested_user, page):
        calls.append((requested_user, page))
        start = (page - 1) * 20
        return [(id, 'pollution', 'active', datetime.now(UTC))
                for id in ids[start:start + 20]], count > start + 20

    monkeypatch.setattr(PostgreSQLAdminReadRepository, 'user_reports', read)
    seen = []
    for page in range(1, max(1, (count + 19) // 20) + 1):
        response = signed_client.get(f'/admin/data/users/{user_id}/reports?page={page}')
        assert response.status_code == 200
        assert response.headers['cache-control'] == 'no-store'
        data = response.json()
        assert data['page'] == page
        assert data['has_more'] == (count > page * 20)
        assert len(data['items']) <= 20
        seen.extend(item['id'] for item in data['items'])
    assert seen == ids
    assert all(id == user_id for id, _ in calls)
    beyond = signed_client.get(f'/admin/data/users/{user_id}/reports?page=99').json()
    assert beyond['items'] == [] and beyond['has_more'] is False


@pytest.mark.parametrize('page', ['0', '-1', '2147483648', 'invalid'])
def test_user_report_page_is_bounded(signed_client, page):
    response = signed_client.get(f'/admin/data/users/{UUID(int=1)}/reports?page={page}')
    assert response.status_code == 422


@pytest.mark.parametrize('path', ['/admin/data/users', '/admin/data/users/00000000-0000-0000-0000-000000000001/reports', '/admin/data/reports?west=-1&south=-1&east=1&north=1'])
def test_data_reads_refuse_missing_session(path):
    client = TestClient(app, base_url='https://testserver')
    assert client.get(path, follow_redirects=False).status_code == 303
