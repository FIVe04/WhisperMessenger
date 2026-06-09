import asyncio
import time


class InMemoryRateLimiter:
    def __init__(self, requests_per_minute: int) -> None:
        self._requests_per_minute = requests_per_minute
        self._store: dict[str, tuple[float, int]] = {}
        self._lock = asyncio.Lock()

    async def allow(self, client_id: str) -> bool:
        now = time.monotonic()

        async with self._lock:
            window_start, count = self._store.get(client_id, (now, 0))
            if now - window_start >= 60:
                window_start, count = now, 0

            if count >= self._requests_per_minute:
                return False

            self._store[client_id] = (window_start, count + 1)
            return True
