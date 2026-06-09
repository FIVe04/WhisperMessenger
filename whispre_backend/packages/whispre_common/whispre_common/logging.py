import json
import logging
import os
import sys
import traceback
from contextvars import ContextVar
from datetime import UTC, datetime
from typing import Any

_service_name: ContextVar[str] = ContextVar('log_service_name', default='unknown')
_request_id: ContextVar[str | None] = ContextVar('log_request_id', default=None)
_user_id: ContextVar[str | None] = ContextVar('log_user_id', default=None)


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            'timestamp': datetime.now(UTC).isoformat(timespec='milliseconds').replace('+00:00', 'Z'),
            'level': record.levelname.lower(),
            'service': _service_name.get(),
            'logger': record.name,
            'event': getattr(record, 'event', 'application_log'),
            'message': record.getMessage(),
        }

        request_id = _request_id.get()
        if request_id:
            payload['request_id'] = request_id

        user_id = _user_id.get()
        if user_id:
            payload['user_id'] = user_id

        fields = getattr(record, 'whispre_fields', None)
        if isinstance(fields, dict):
            payload.update({key: _json_value(value) for key, value in fields.items() if value is not None})

        if record.exc_info:
            payload['exception'] = ''.join(traceback.format_exception(*record.exc_info)).rstrip()

        return json.dumps(payload, ensure_ascii=True, separators=(',', ':'))


def _json_value(value: Any) -> Any:
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    if isinstance(value, datetime):
        return value.astimezone(UTC).isoformat().replace('+00:00', 'Z')
    return str(value)


def configure_logging(service_name: str) -> None:
    _service_name.set(service_name)
    level_name = os.getenv('LOG_LEVEL', 'INFO').upper()
    level = getattr(logging, level_name, logging.INFO)

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())

    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level)

    for logger_name in ('uvicorn', 'uvicorn.error', 'fastapi'):
        logger = logging.getLogger(logger_name)
        logger.handlers = []
        logger.propagate = True
        logger.setLevel(level)

    for logger_name in ('httpx', 'httpcore', 'aiokafka'):
        logging.getLogger(logger_name).setLevel(logging.WARNING)

    # HTTP access is emitted by Whispre middleware with route templates and request IDs.
    logging.getLogger('uvicorn.access').disabled = True


def set_request_context(request_id: str) -> None:
    _request_id.set(request_id)
    _user_id.set(None)


def bind_user_id(user_id: str) -> None:
    _user_id.set(user_id)


def clear_request_context() -> None:
    _request_id.set(None)
    _user_id.set(None)


def log_event(
    logger: logging.Logger,
    level: int,
    event: str,
    message: str | None = None,
    *,
    exc_info: bool = False,
    **fields: Any,
) -> None:
    logger.log(
        level,
        message or event,
        extra={'event': event, 'whispre_fields': fields},
        exc_info=exc_info,
    )
