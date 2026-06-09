from collections.abc import Mapping

from fastapi import HTTPException, status

from .config import settings

ROUTE_TABLE: list[tuple[str, str]] = [
    ('/v1/auth', settings.auth_service_url),
    ('/v1/users', settings.user_service_url),
    ('/v1/keys', settings.key_service_url),
    ('/v1/conversations', settings.conversation_service_url),
    ('/v1/messages', settings.message_service_url),
    ('/v1/realtime', settings.realtime_service_url),
    ('/v1/notifications', settings.notification_service_url),
]

HOP_BY_HOP_HEADERS = {
    'connection',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'te',
    'trailers',
    'transfer-encoding',
    'upgrade',
    'host',
}


def pick_target(path: str) -> str:
    for prefix, target in ROUTE_TABLE:
        if path.startswith(prefix):
            return target
    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='No route for path')


def clean_headers(headers: Mapping[str, str]) -> dict[str, str]:
    return {key: value for key, value in headers.items() if key.lower() not in HOP_BY_HOP_HEADERS}
