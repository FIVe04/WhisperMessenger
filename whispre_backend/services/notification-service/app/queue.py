import asyncio
from collections import deque

from .config import settings


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
