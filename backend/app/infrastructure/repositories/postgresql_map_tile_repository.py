from uuid import UUID

from app.application.ports.map_tile_repository import MapTileRepository
from app.domain.report import ReportCategory
from app.infrastructure.database.connection import database_connection


class PostgreSQLMapTileRepository(MapTileRepository):
    """Build Mapbox Vector Tiles from current report locations."""

    def get_tile(
        self,
        *,
        zoom: int,
        x: int,
        y: int,
        category: ReportCategory | None = None,
        report_id: UUID | None = None,
    ) -> bytes:
        query = """
            WITH request AS (
                SELECT
                    %s::integer AS zoom,
                    %s::integer AS x,
                    %s::integer AS y,
                    %s::text AS category,
                    %s::uuid AS report_id
            ), tile AS (
                SELECT
                    ST_TileEnvelope(zoom, x, y) AS bounds,
                    ST_TileEnvelope(
                        zoom,
                        x,
                        y,
                        margin => 64.0 / 4096
                    ) AS query_bounds,
                    zoom,
                    category,
                    report_id
                FROM request
            ), visible_reports AS (
                SELECT
                    report.id,
                    report.category,
                    ST_Transform(report.final_position::geometry, 3857) AS point
                FROM nowave.reports AS report
                CROSS JOIN tile
                WHERE report.status = 'active'
                  AND report.expires_at > statement_timestamp()
                  AND report.final_position::geometry &&
                      ST_Transform(tile.query_bounds, 4326)
                  AND ST_Intersects(
                      report.final_position::geometry,
                      ST_Transform(tile.query_bounds, 4326)
                  )
                  AND (tile.category IS NULL OR report.category = tile.category)
                  AND (tile.report_id IS NULL OR report.id = tile.report_id)
            ), grouped_reports AS (
                -- At low zooms, cluster points within 3.5 percent of a tile width.
                -- At high zooms, each report stays separate.
                SELECT
                    visible_reports.*,
                    CASE
                        WHEN tile.zoom <= 8 AND tile.report_id IS NULL
                            THEN ST_ClusterDBSCAN(
                                visible_reports.point,
                                eps => 40075016.68557849 / power(2, tile.zoom) * 0.035,
                                minpoints => 2
                            ) OVER ()::text
                        ELSE NULL
                    END AS cluster_id
                FROM visible_reports
                CROSS JOIN tile
            ), map_features AS (
                SELECT
                    CASE WHEN COUNT(*) = 1 THEN MIN(id::text) END AS report_id,
                    CASE WHEN COUNT(*) = 1 THEN MIN(category) END AS category,
                    COUNT(*) > 1 AS cluster,
                    COUNT(*)::integer AS cluster_count,
                    ST_Centroid(ST_Collect(point)) AS point
                FROM grouped_reports
                GROUP BY COALESCE(cluster_id, id::text)
            ), tile_features AS (
                SELECT
                    map_features.report_id,
                    map_features.category,
                    map_features.cluster,
                    map_features.cluster_count,
                    ST_AsMVTGeom(
                        map_features.point,
                        tile.bounds,
                        extent => 4096,
                        buffer => 64,
                        clip_geom => true
                    ) AS geom
                FROM map_features
                CROSS JOIN tile
            )
            SELECT COALESCE(
                ST_AsMVT(tile_features, 'reports', 4096, 'geom'),
                '\\x'::bytea
            )
            FROM tile_features
            WHERE geom IS NOT NULL
        """
        values = (
            zoom,
            x,
            y,
            category.value if category is not None else None,
            report_id,
        )

        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(query, values)
                row = cursor.fetchone()

        return row[0] if row and row[0] is not None else b""
