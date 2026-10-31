"""Translate asyncio cancellation without interrupting HTTPcore cleanup."""

import asyncio
from collections.abc import Awaitable, Callable
from typing import TypeVar

import anyio

_T = TypeVar("_T")


async def cancellation_safe(operation: Callable[[], Awaitable[_T]]) -> _T:
    """Translate raw Task.cancel() into AnyIO cancellation and join cleanup."""
    # Deliver pending cancellation before starting I/O.
    await asyncio.sleep(0)
    scope = anyio.CancelScope()

    async def run() -> _T:
        with scope:
            if scope.cancel_called:
                raise asyncio.CancelledError
            return await operation()
        # The scope suppresses its own cancellation; preserve that result.
        raise asyncio.CancelledError

    task = asyncio.create_task(run())
    try:
        return await asyncio.shield(task)
    except asyncio.CancelledError as cancellation:
        scope.cancel()
        # AnyIO shields avoid busy-spinning; asyncio shields handle Task.cancel().
        with anyio.CancelScope(shield=True):
            while not task.done():
                try:
                    await asyncio.shield(task)
                except asyncio.CancelledError:
                    pass
                except BaseException:
                    break
            if not task.cancelled():
                try:
                    task.result()
                except BaseException as cleanup_error:
                    raise cancellation from cleanup_error
        raise
