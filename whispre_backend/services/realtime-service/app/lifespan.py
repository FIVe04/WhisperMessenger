import asyncio
import contextlib
from contextlib import asynccontextmanager

from fastapi import FastAPI

from .consumer import consume_envelope_events


@asynccontextmanager
async def lifespan(_app: FastAPI):
    task = asyncio.create_task(consume_envelope_events())
    try:
        yield
    finally:
        task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await task
