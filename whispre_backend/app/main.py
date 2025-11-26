from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

from app.database import init_db
from app.routes.devices import router as devices_router
from app.routes.messages import router as messages_router
from app.routes.users import router as users_router
from app.routes.sessions import router as sessions_router
from app.websocket import router as ws_router
from app.routes.keys import router as keys_router

from app.config import settings


@asynccontextmanager
async def lifespan(app: FastAPI):
    print('[SUCCESS] App started')
    init_db()
    print('[SUCCESS] DB connected')
    yield
    print('[FAILURE] App stopped')


app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
)

app.include_router(devices_router)
app.include_router(messages_router)
app.include_router(users_router)
app.include_router(sessions_router)
app.include_router(keys_router)
app.include_router(ws_router)




