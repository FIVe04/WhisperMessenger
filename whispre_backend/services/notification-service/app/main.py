import asyncio
import contextlib
import json
import logging
import uuid
from collections import deque
from contextlib import asynccontextmanager
from datetime import UTC, datetime

from aiokafka import AIOKafkaConsumer
from fastapi import Depends, FastAPI, HTTPException, Query, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .config import settings
from .db import get_db
from .schemas import PendingNotification
from .security import decode_access_token

SERVICE_NAME = settings.service_name
security = HTTPBearer(auto_error=True)
logger = logging.getLogger(SERVICE_NAME)


class NotificationQueue:
    def __init__(self, max_per_device: int) -> None:
        self._queues: dict[str, deque[dict]] = {}
        self._max_per_device = max_per_device
        self._lock = asyncio.Lock()

    async def push(self, device_id: str, notification: dict) -> None:
        async with self._lock:
            queue = self._queues.setdefault(device_id, deque(maxlen=self._max_per_device))
            queue.append(notification)

    async def list_for_device(self, device_id: str, limit: int) -> list[dict]:
        async with self._lock:
            queue = self._queues.get(device_id, deque())
            return list(queue)[-limit:]

    async def ack(self, device_id: str, notification_id: str) -> bool:
        async with self._lock:
            queue = self._queues.get(device_id)
            if not queue:
                return False

            for item in list(queue):
                if item['notification_id'] == notification_id:
                    queue.remove(item)
                    return True
            return False


notification_queue = NotificationQueue(settings.queue_max_per_device)


async def consume_events() -> None:
    while True:
        consumer = AIOKafkaConsumer(
            settings.kafka_topic_envelope_accepted,
            bootstrap_servers=settings.kafka_broker,
            group_id=settings.kafka_consumer_group,
            enable_auto_commit=True,
            auto_offset_reset='latest',
        )
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

                notification = {
                    'notification_id': str(uuid.uuid4()),
                    'type': 'new_envelope',
                    'envelope_id': payload.get('envelope_id', ''),
                    'conversation_id': payload.get('conversation_id', ''),
                    'sender_user_id': payload.get('sender_user_id', ''),
                    'recipient_device_id': recipient_device_id,
                    'created_at': datetime.now(UTC),
                }
                await notification_queue.push(recipient_device_id, notification)
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
    task = asyncio.create_task(consume_events())
    app.state.kafka_task = task

    try:
        yield
    finally:
        task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await task


app = FastAPI(title=f'Whispre {SERVICE_NAME}', lifespan=lifespan)


def require_auth(credentials: HTTPAuthorizationCredentials = Depends(security)) -> str:
    payload = decode_access_token(credentials.credentials)
    return str(payload['sub'])


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


@app.get('/v1/notifications/pending', response_model=list[PendingNotification])
async def get_pending_notifications(
    device_id: str = Query(...),
    limit: int = Query(default=100, ge=1, le=1000),
    current_user_id: str = Depends(require_auth),
) -> list[PendingNotification]:
    ensure_device_owner(current_user_id, device_id)
    items = await notification_queue.list_for_device(device_id, limit)
    return [PendingNotification(**item) for item in items]


@app.post('/v1/notifications/{notification_id}/ack')
async def ack_notification(
    notification_id: str,
    device_id: str = Query(...),
    current_user_id: str = Depends(require_auth),
) -> dict[str, str]:
    ensure_device_owner(current_user_id, device_id)
    ok = await notification_queue.ack(device_id, notification_id)
    if not ok:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Notification not found')
    return {'status': 'ok'}
