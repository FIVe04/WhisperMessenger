from contextlib import asynccontextmanager

from fastapi import FastAPI

from .producer import envelope_event_producer


@asynccontextmanager
async def lifespan(_app: FastAPI):
    await envelope_event_producer.start()
    try:
        yield
    finally:
        await envelope_event_producer.stop()
