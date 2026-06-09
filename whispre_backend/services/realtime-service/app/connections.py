import asyncio
import logging

from fastapi import WebSocket
from whispre_common.logging import log_event
from whispre_common.observability import websocket_connected, websocket_disconnected

from .config import settings

logger = logging.getLogger('realtime-service.websocket')


class DeviceConnectionManager:
    def __init__(self) -> None:
        self._connections: dict[str, set[WebSocket]] = {}
        self._lock = asyncio.Lock()

    async def connect(self, device_id: str, websocket: WebSocket) -> None:
        await websocket.accept()
        async with self._lock:
            self._connections.setdefault(device_id, set()).add(websocket)
            device_connections = len(self._connections[device_id])
        websocket_connected(settings.service_name)
        log_event(
            logger,
            logging.INFO,
            'websocket_connected',
            device_id=device_id,
            device_connections=device_connections,
        )

    async def disconnect(self, device_id: str, websocket: WebSocket) -> None:
        removed = False
        async with self._lock:
            if device_id in self._connections:
                removed = websocket in self._connections[device_id]
                self._connections[device_id].discard(websocket)
                if not self._connections[device_id]:
                    self._connections.pop(device_id, None)
        if removed:
            websocket_disconnected(settings.service_name)
            log_event(logger, logging.INFO, 'websocket_disconnected', device_id=device_id)

    async def push(self, device_id: str, payload: dict) -> None:
        async with self._lock:
            sockets = list(self._connections.get(device_id, set()))

        for websocket in sockets:
            try:
                await websocket.send_json(payload)
            except Exception:
                log_event(
                    logger,
                    logging.WARNING,
                    'websocket_push_failed',
                    device_id=device_id,
                    event_type=payload.get('type'),
                    exc_info=True,
                )
                await self.disconnect(device_id, websocket)

        log_event(
            logger,
            logging.INFO,
            'websocket_event_dispatched',
            device_id=device_id,
            event_type=payload.get('type'),
            envelope_id=payload.get('envelope_id'),
            connection_count=len(sockets),
        )


connection_manager = DeviceConnectionManager()
