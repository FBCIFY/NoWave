"""Optional coastline context failures must not invalidate mandatory geometry."""

import asyncio
from io import BytesIO

import numpy as np
import pytest
from PIL import Image

from app.domain.marine import ProviderUnavailable
from app.domain.marine_tile import Tile
from app.infrastructure.marine.coastline import CoastlineMask
from app.infrastructure.marine.visual_water import PADDING, SIZE


CENTRE = Tile(14, 8462, 6014)
WEST = Tile(14, 8461, 6014)
DIM = SIZE + 2 * PADDING
OFFSETS = {(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)} - {(0, 0)}


def png(image):
    output = BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


def raw(*, corners=False):
    image = Image.new("RGBA", (DIM, DIM), (40, 140, 160, 255))
    points = [(PADDING, 100)]
    if corners:
        points = [
            (x, y)
            for x in (PADDING, PADDING + SIZE - 1)
            for y in (PADDING, PADDING + SIZE - 1)
        ]
    for point in points:
        image.putpixel(point, (0, 0, 0, 0))
    return png(image)


@pytest.mark.parametrize(
    "failed", [set(), {(-1, 0)}, {(-1, 0), (0, -1), (-1, -1)}, OFFSETS]
)
def test_available_context_is_exact_and_missing_neighbours_remain_zero(
    monkeypatch, failed
):
    async def scenario():
        coast = CoastlineMask(None)
        mask = Image.new("L", (SIZE, SIZE), 255)
        mask.paste(0, (100, 100, 120, 120))
        content = png(mask)
        requested = []

        async def get_mask(tile):
            offset = (tile.x - CENTRE.x, tile.y - CENTRE.y)
            requested.append(offset)
            if offset in failed:
                raise ProviderUnavailable("optional neighbour unavailable")
            return content

        monkeypatch.setattr(coast, "get_mask", get_mask)
        result = await coast.get_context(CENTRE, raw(corners=True))
        expected = Image.new("L", (DIM, DIM), 0)
        for dx, dy in {(0, 0)} | (OFFSETS - failed):
            expected.paste(mask, (PADDING + dx * SIZE, PADDING + dy * SIZE))
        assert result.complete == (not failed)
        assert np.array_equal(np.array(result.mask), np.array(expected))
        assert result.mask.getpixel((PADDING + 110, PADDING + 110)) == 0
        assert requested[0] == (0, 0)
        assert set(requested) == OFFSETS | {(0, 0)}

    asyncio.run(scenario())


@pytest.mark.parametrize("target", [CENTRE, WEST])
def test_cancelled_mask_is_propagated_and_never_becomes_optional_fallback(
    monkeypatch, target
):
    async def scenario():
        coast = CoastlineMask(None)

        async def get_mask(tile):
            if tile == target:
                raise asyncio.CancelledError()
            return png(Image.new("L", (SIZE, SIZE), 255))

        monkeypatch.setattr(coast, "get_mask", get_mask)
        with pytest.raises(asyncio.CancelledError):
            await coast.get_context(CENTRE, raw())

    asyncio.run(scenario())


@pytest.mark.parametrize("error", [RuntimeError, AssertionError, TypeError, ValueError])
def test_neighbour_programming_errors_are_not_treated_as_unavailability(
    monkeypatch, error
):
    async def scenario():
        coast = CoastlineMask(None)

        async def get_mask(tile):
            if tile == WEST:
                raise error("programming error")
            return png(Image.new("L", (SIZE, SIZE), 255))

        monkeypatch.setattr(coast, "get_mask", get_mask)
        with pytest.raises(error, match="programming error"):
            await coast.get_context(CENTRE, raw())

    asyncio.run(scenario())


def test_neighbours_are_concurrent_and_cancelling_context_cancels_pending_calls(
    monkeypatch,
):
    async def scenario():
        coast = CoastlineMask(None)
        started, release = asyncio.Event(), asyncio.Event()
        entered, cancelled = set(), set()
        content = png(Image.new("L", (SIZE, SIZE), 255))

        async def get_mask(tile):
            if tile == CENTRE:
                return content
            entered.add(tile)
            if len(entered) == 8:
                started.set()
            try:
                await release.wait()
            finally:
                cancelled.add(tile)
            return content

        monkeypatch.setattr(coast, "get_mask", get_mask)
        pending = asyncio.create_task(coast.get_context(CENTRE, raw(corners=True)))
        await asyncio.wait_for(started.wait(), 2)
        assert not pending.done()
        pending.cancel()
        with pytest.raises(asyncio.CancelledError):
            await pending
        assert cancelled == entered
        assert len(cancelled) == 8

    asyncio.run(scenario())
