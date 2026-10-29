from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Response

from app.api.schemas.public_observation import PublicObservationPageResponse
from app.application.ports.public_observation_reader import ObservationQuery, PublicObservationReader
from app.application.services.list_public_observations import ListPublicObservations, decode_observation_cursor
from app.domain.report import ReportCategory
from app.infrastructure.repositories.postgresql_public_observation_repository import PostgreSQLPublicObservationRepository


router = APIRouter(prefix="/map", tags=["map"])


def get_public_observation_reader() -> PublicObservationReader:
    return PostgreSQLPublicObservationRepository()


@router.get("/observations", response_model=PublicObservationPageResponse, response_model_exclude_none=True)
def get_public_observations(
    response: Response,
    reader: Annotated[PublicObservationReader, Depends(get_public_observation_reader)],
    west: Annotated[float | None, Query(ge=-180, le=180, allow_inf_nan=False)] = None,
    south: Annotated[float | None, Query(ge=-90, le=90, allow_inf_nan=False)] = None,
    east: Annotated[float | None, Query(ge=-180, le=180, allow_inf_nan=False)] = None,
    north: Annotated[float | None, Query(ge=-90, le=90, allow_inf_nan=False)] = None,
    category: ReportCategory | None = None,
    q: Annotated[str, Query(max_length=120)] = "",
    limit: Annotated[int, Query(ge=1, le=500)] = 200,
    cursor: Annotated[str | None, Query(min_length=1, max_length=160)] = None,
):
    """Public observation station: active reports and consented public fields.

    Omit all four bounds for a global query. west > east crosses the dateline.
    Pagination keeps the same bounds and filters and follows next_cursor.
    Removed and expired reports disappear on every fresh request.
    """
    bounds = (west, south, east, north)
    if any(value is not None for value in bounds):
        if any(value is None for value in bounds) or south >= north or west == east:
            raise HTTPException(status_code=422, detail="Provide four nonempty map bounds")
    else:
        west, south, east, north = -180, -90, 180, 90
    try:
        after = decode_observation_cursor(cursor)
    except ValueError as error:
        raise HTTPException(status_code=422, detail="Invalid observation cursor") from error
    query = ObservationQuery(
        west=west, south=south, east=east, north=north,
        category=category, q=q.strip(), limit=limit, after=after,
    )
    response.headers["Cache-Control"] = "no-store"
    return ListPublicObservations(reader).execute(query)
