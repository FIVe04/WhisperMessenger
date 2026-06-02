import asyncio
import contextlib
import json
import logging
from contextlib import asynccontextmanager

from aiokafka import AIOKafkaConsumer
from fastapi import FastAPI, HTTPException, Query, WebSocket, WebSocketDisconnect, status

from .config import settings
from .db import get_db
from .security import decode_access_token

SERVICE_NAME = settings.service_name
logger = logging.getLogger(SERVICE_NAME)


class DeviceConnectionManager:
    def __init__(self) -> None:
        self._connections: dict[str, set[WebSocket]] = {}
        self._lock = asyncio.Lock()

    async def connect(self, device_id: str, websocket: WebSocket) -> None:
        await websocket.accept()
        async with self._lock:
            self._connections.setdefault(device_id, set()).add(websocket)

    async def disconnect(self, device_id: str, websocket: WebSocket) -> None:
        async with self._lock:
            if device_id in self._connections:
                self._connections[device_id].discard(websocket)
                if not self._connections[device_id]:
                    self._connections.pop(device_id, None)

    async def push(self, device_id: str, payload: dict) -> None:
        async with self._lock:
            sockets = list(self._connections.get(device_id, set()))

        for ws in sockets:
            try:
                await ws.send_json(payload)
            except Exception:
                await self.disconnect(device_id, ws)


manager = DeviceConnectionManager()


async def consume_envelope_events(consumer: AIOKafkaConsumer) -> None:
    while True:
        try:
            await consumer.start()
            logger.info('Kafka consumer started')
            async for msg in consumer:
                try:
                    payload = json.loads(msg.value.decode('utf-8'))
                except Exception:
                    continue
                recipient_device_id = payload.get('recipient_device_id')
                if not recipient_device_id:
                    continue

                await manager.push(
                    recipient_device_id,
                    {
                        'type': 'new_envelope',
                        'envelope_id': payload.get('envelope_id'),
                        'conversation_id': payload.get('conversation_id'),
                        'sender_user_id': payload.get('sender_user_id'),
                        'recipient_device_id': recipient_device_id,
                    },
                )
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            logger.warning('Kafka consumer failed: %s. Retrying in 2s', exc)
            await asyncio.sleep(2)
        finally:
            with contextlib.suppress(Exception):
                await consumer.stop()


@asynccontextmanager
async def lifespan(app: FastAPI):
    consumer = AIOKafkaConsumer(
        settings.kafka_topic_envelope_accepted,
        bootstrap_servers=settings.kafka_broker,
        group_id=settings.kafka_consumer_group,
        enable_auto_commit=True,
        auto_offset_reset='latest',
    )
    task = asyncio.create_task(consume_envelope_events(consumer))
    app.state.kafka_task = task

    try:
        yield
    finally:
        task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await task


app = FastAPI(title=f'Whispre {SERVICE_NAME}', lifespan=lifespan)


def extract_bearer_token(websocket: WebSocket) -> str:
    auth_header = websocket.headers.get('authorization', '')
    if not auth_header.lower().startswith('bearer '):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Missing bearer token')
    return auth_header[7:]


def ensure_device_owner(user_id: str, device_id: str) -> None:
    with get_db() as conn:
        row = conn.execute('select user_id::text as user_id from devices where id = %s', (device_id,)).fetchone()
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Device not found')
    if row['user_id'] != user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Device does not belong to user')


@app.get('/health')
def health() -> dict[str, str]:
    return {'status': 'ok', 'service': SERVICE_NAME}


@app.websocket('/v1/realtime/ws')
async def realtime_ws(websocket: WebSocket, device_id: str = Query(...)):
    try:
        token = extract_bearer_token(websocket)
        payload = decode_access_token(token)
        current_user_id = str(payload['sub'])
        ensure_device_owner(current_user_id, device_id)
    except HTTPException:
        await websocket.close(code=1008)
        return

    await manager.connect(device_id, websocket)
    await websocket.send_json({'type': 'connected', 'device_id': device_id})

    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        await manager.disconnect(device_id, websocket)
