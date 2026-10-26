from datetime import UTC, datetime, timedelta, timezone
from uuid import uuid4

import pytest

from app.application.services.admin_reads import (
    AdminReadService,
)
from app.domain.errors import ReportNotFoundError
from app.domain.pagination import (
    MAX_PAGE,
    MAX_PAGE_LIMIT,
    Page,
    page_offset,
    validate_page,
)
from app.domain.report import ReportStatus
from app.domain.user import UserStatus


NOW = datetime(2026, 10, 12, 12, 0, tzinfo=UTC)


class FakeAdminReadRepository:
    def __init__(self, report=None):
        self.report = report
        self.calls = []

    def _page(self, name, values):
        self.calls.append((name, values))

        return Page(
            items=[],
            page=values["page"],
            limit=values["limit"],
            total=0,
        )

    def list_reports(self, **values):
        return self._page("list_reports", values)

    def get_report(self, **values):
        self.calls.append(("get_report", values))
        return self.report

    def list_users(self, **values):
        return self._page("list_users", values)

    def list_moderation_actions(self, **values):
        return self._page("list_moderation_actions", values)


def create_service(report=None):
    repository = FakeAdminReadRepository(report)

    return AdminReadService(
        admin_read_repository=repository,
    ), repository


@pytest.mark.parametrize(
    "total,limit,pages",
    [
        (0, 20, 0),
        (1, 20, 1),
        (20, 20, 1),
        (21, 20, 2),
        (100, 1, 100),
    ],
)
def test_page_count(total, limit, pages):
    page = Page(items=[], page=1, limit=limit, total=total)

    assert page.pages == pages


def test_page_offset():
    assert page_offset(1, 20) == 0
    assert page_offset(3, 20) == 40


@pytest.mark.parametrize(
    "page,limit",
    [
        (0, 20),
        (MAX_PAGE + 1, 20),
        (1, 0),
        (1, MAX_PAGE_LIMIT + 1),
    ],
)
def test_validate_page_rejects_out_of_range_values(page, limit):
    with pytest.raises(ValueError):
        validate_page(page, limit)


def test_list_reports_passes_filters_and_utc_now():
    service, repository = create_service()
    paris_now = NOW.astimezone(timezone(timedelta(hours=2)))

    service.list_reports(
        page=2,
        limit=10,
        status=ReportStatus.EXPIRED,
        now=paris_now,
    )

    name, values = repository.calls[0]

    assert name == "list_reports"
    assert values == {
        "page": 2,
        "limit": 10,
        "status": ReportStatus.EXPIRED,
        "now": NOW,
    }
    assert values["now"].tzinfo == UTC


def test_list_reports_requires_timezone():
    service, repository = create_service()

    with pytest.raises(ValueError):
        service.list_reports(
            now=datetime(2026, 10, 12, 12, 0),
        )

    assert repository.calls == []


def test_invalid_page_never_reaches_repository():
    service, repository = create_service()

    with pytest.raises(ValueError):
        service.list_users(page=0)

    with pytest.raises(ValueError):
        service.list_moderation_actions(limit=MAX_PAGE_LIMIT + 1)

    assert repository.calls == []


def test_list_users_passes_status_filter():
    service, repository = create_service()

    service.list_users(status=UserStatus.SUSPENDED)

    assert repository.calls == [
        (
            "list_users",
            {
                "page": 1,
                "limit": 20,
                "status": UserStatus.SUSPENDED,
            },
        )
    ]


@pytest.mark.parametrize("report_id", [None, uuid4()])
def test_list_moderation_actions_passes_report_filter(report_id):
    service, repository = create_service()

    service.list_moderation_actions(page=2, limit=20, report_id=report_id)

    assert repository.calls == [
        (
            "list_moderation_actions",
            {"page": 2, "limit": 20, "report_id": report_id},
        )
    ]


def test_get_report_returns_repository_report():
    report = object()
    service, repository = create_service(report)
    report_id = uuid4()

    assert service.get_report(report_id, now=NOW) is report
    assert repository.calls == [
        (
            "get_report",
            {
                "report_id": report_id,
                "now": NOW,
            },
        )
    ]


def test_get_missing_report_raises_not_found():
    service, _ = create_service(None)

    with pytest.raises(ReportNotFoundError):
        service.get_report(uuid4(), now=NOW)
