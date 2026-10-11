from dataclasses import dataclass
from math import ceil
from typing import Generic, TypeVar


T = TypeVar("T")

DEFAULT_PAGE_LIMIT = 20
MAX_PAGE_LIMIT = 100

# Keeps (page - 1) * limit far below the PostgreSQL bigint OFFSET limit.
MAX_PAGE = 1_000_000


def validate_page(page: int, limit: int) -> None:
    if not 1 <= page <= MAX_PAGE:
        raise ValueError(
            f"page must be between 1 and {MAX_PAGE}"
        )

    if not 1 <= limit <= MAX_PAGE_LIMIT:
        raise ValueError(
            f"limit must be between 1 and {MAX_PAGE_LIMIT}"
        )


def page_offset(page: int, limit: int) -> int:
    validate_page(page, limit)

    return (page - 1) * limit


@dataclass(frozen=True)
class Page(Generic[T]):
    """One page of a list. total counts every matching row,
    not only the items of this page."""

    items: list[T]
    page: int
    limit: int
    total: int

    @property
    def pages(self) -> int:
        return ceil(self.total / self.limit)
