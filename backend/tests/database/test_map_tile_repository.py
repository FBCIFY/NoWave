from datetime import UTC, datetime, timedelta
from math import asinh, pi, radians, tan
from uuid import uuid4

import psycopg

from app.domain.report import Report, ReportCategory
from app.domain.user import User
from app.infrastructure.repositories.postgresql_map_tile_repository import (
    PostgreSQLMapTileRepository,
)
from app.infrastructure.repositories.postgresql_report_repository import (
    PostgreSQLReportRepository,
)
from app.infrastructure.repositories.postgresql_user_repository import (
    PostgreSQLUserRepository,
)


def tile_for_position(longitude: float, latitude: float, zoom: int) -> tuple[int, int]:
    tiles_per_axis = 1 << zoom
    latitude_radians = radians(latitude)
    x = int((longitude + 180) / 360 * tiles_per_axis)
    y = int((1 - asinh(tan(latitude_radians)) / pi) / 2 * tiles_per_axis)
    return x, y


def test_tile_uses_position_category_status_and_live_expiration(dsn, monkeypatch):
    monkeypatch.setenv("DATABASE_URL", dsn)
    user = User(
        firebase_uid=f"map-tile-{uuid4()}",
        username=f"map-tile-{uuid4()}",
        email=f"map-tile-{uuid4()}@nowave.test",
    )
    PostgreSQLUserRepository().save(user)

    longitude, latitude = 150.0, -30.0
    report = Report.create_manual(
        author_id=user.id,
        client_report_id=uuid4(),
        category=ReportCategory.POLLUTION,
        longitude=longitude,
        latitude=latitude,
        observed_at=datetime.now(UTC) - timedelta(minutes=5),
    )
    PostgreSQLReportRepository().save(report)

    x, y = tile_for_position(longitude, latitude, zoom=9)
    repository = PostgreSQLMapTileRepository()
    tile = repository.get_tile(zoom=9, x=x, y=y, report_id=report.id)

    assert tile
    assert repository.get_tile(zoom=0, x=0, y=0, report_id=report.id)
    assert repository.get_tile(
        zoom=9, x=x, y=y, category=ReportCategory.OBSTRUCTION,
        report_id=report.id,
    ) == b""
    assert repository.get_tile(zoom=9, x=x, y=y, report_id=uuid4()) == b""

    with psycopg.connect(dsn) as connection:
        connection.execute(
            """
            UPDATE nowave.reports
            SET status = 'removed', removed_at = now(), updated_at = now()
            WHERE id = %s
            """,
            (report.id,),
        )

    assert repository.get_tile(zoom=9, x=x, y=y, report_id=report.id) == b""

    expired_report_id = uuid4()
    observed_at = datetime.now(UTC) - timedelta(hours=25)
    with psycopg.connect(dsn) as connection:
        connection.execute(
            """
            INSERT INTO nowave.reports (
                id, author_id, client_report_id, category,
                positioning_mode, final_position, observed_at, created_at,
                expires_at, status, updated_at
            ) VALUES (
                %s, %s, %s, 'pollution', 'manual',
                ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography,
                %s, now(), %s, 'active', now()
            )
            """,
            (
                expired_report_id, user.id, uuid4(), longitude, latitude,
                observed_at, observed_at + timedelta(hours=24),
            ),
        )

    assert repository.get_tile(
        zoom=9, x=x, y=y, report_id=expired_report_id,
    ) == b""


def _read_varint(data: bytes, offset: int) -> tuple[int, int]:
    value = 0
    shift = 0
    while True:
        part = data[offset]
        offset += 1
        value |= (part & 0x7F) << shift
        if part < 0x80:
            return value, offset
        shift += 7


def _binary_fields(data: bytes, field_number: int) -> list[bytes]:
    """Read the length-delimited fields needed to count MVT features."""
    fields = []
    offset = 0
    while offset < len(data):
        tag, offset = _read_varint(data, offset)
        number, wire_type = tag >> 3, tag & 7
        if wire_type == 0:
            _, offset = _read_varint(data, offset)
        elif wire_type == 2:
            length, offset = _read_varint(data, offset)
            value = data[offset : offset + length]
            offset += length
            if number == field_number:
                fields.append(value)
        else:
            raise AssertionError(f"Unexpected MVT wire type: {wire_type}")
    return fields


def _feature_count(tile: bytes) -> int:
    # MVT Tile uses field 3 for layers and Layer uses field 2 for features.
    return sum(len(_binary_fields(layer, 2)) for layer in _binary_fields(tile, 3))


def test_nearby_reports_form_one_cluster_until_zoom_nine(dsn, monkeypatch):
    monkeypatch.setenv("DATABASE_URL", dsn)
    user = User(
        firebase_uid=f"tile-cluster-{uuid4()}",
        username=f"tile-cluster-{uuid4()}",
        email=f"tile-cluster-{uuid4()}@nowave.test",
    )
    PostgreSQLUserRepository().save(user)

    for longitude, latitude in [(100.0, -20.0), (100.001, -20.001)]:
        report = Report.create_manual(
            author_id=user.id,
            client_report_id=uuid4(),
            category=ReportCategory.MARINE_ANIMAL,
            longitude=longitude,
            latitude=latitude,
            observed_at=datetime.now(UTC) - timedelta(minutes=5),
        )
        PostgreSQLReportRepository().save(report)

    repository = PostgreSQLMapTileRepository()
    low_x, low_y = tile_for_position(100.0, -20.0, zoom=8)
    high_x, high_y = tile_for_position(100.0, -20.0, zoom=9)

    low_zoom_tile = repository.get_tile(zoom=8, x=low_x, y=low_y)
    high_zoom_tile = repository.get_tile(zoom=9, x=high_x, y=high_y)

    assert _feature_count(low_zoom_tile) == 1
    assert _feature_count(high_zoom_tile) == 2
