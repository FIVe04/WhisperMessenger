import asyncio
import time
from collections.abc import Mapping

import httpx
import jwt
from fastapi import FastAPI, HTTPException, Request, Response, status
from fastapi.responses import JSONResponse

from .config import settings

SERVICE_NAME = settings.service_name

app = FastAPI(title=f'Whispre {SERVICE_NAME}')

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

AUTH_BYPASS_PREFIXES = (
    '/v1/auth/',
    '/health',
)

rate_limit_store: dict[str, tuple[float, int]] = {}
rate_limit_lock = asyncio.Lock()


def pick_target(path: str) -> str:
    for prefix, target in ROUTE_TABLE:
        if path.startswith(prefix):
            return target
    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='No route for path')


def clean_headers(headers: Mapping[str, str]) -> dict[str, str]:
    return {k: v for k, v in headers.items() if k.lower() not in HOP_BY_HOP_HEADERS}


def is_auth_bypassed(path: str) -> bool:
    return any(path.startswith(prefix) for prefix in AUTH_BYPASS_PREFIXES)


def extract_client_id(request: Request) -> str:
    forwarded_for = request.headers.get('x-forwarded-for')
    if forwarded_for:
        return forwarded_for.split(',')[0].strip()
    if request.client:
        return request.client.host
    return 'unknown'


def validate_access_token(auth_header: str) -> None:
    if not auth_header.lower().startswith('bearer '):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Missing bearer token')

    token = auth_header[7:]
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except jwt.PyJWTError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid token') from exc

    if payload.get('typ') != 'access':
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid token type')


async def check_rate_limit(client_id: str) -> bool:
    now = time.monotonic()
    limit = settings.rate_limit_requests_per_minute

    async with rate_limit_lock:
        window_start, count = rate_limit_store.get(client_id, (now, 0))

        if now - window_start >= 60:
            window_start, count = now, 0

        if count >= limit:
            return False

        rate_limit_store[client_id] = (window_start, count + 1)
        return True


@app.middleware('http')
async def auth_and_rate_middleware(request: Request, call_next):
    path = request.url.path

    if path.startswith('/v1/'):
        client_id = extract_client_id(request)
        allowed = await check_rate_limit(client_id)
        if not allowed:
            return JSONResponse(status_code=status.HTTP_429_TOO_MANY_REQUESTS, content={'detail': 'Rate limit exceeded'})

        if not is_auth_bypassed(path):
            auth_header = request.headers.get('authorization', '')
            try:
                validate_access_token(auth_header)
            except HTTPException as exc:
                return JSONResponse(status_code=exc.status_code, content={'detail': exc.detail})

    return await call_next(request)


@app.get('/health')
def health() -> dict[str, str]:
    return {'status': 'ok', 'service': SERVICE_NAME}


@app.api_route('/v1/{path:path}', methods=['GET', 'POST', 'PUT', 'PATCH', 'DELETE'])
async def proxy_v1(path: str, request: Request) -> Response:
    full_path = f'/v1/{path}'
    target_base = pick_target(full_path)
    target_url = f'{target_base}{full_path}'
    if request.url.query:
        target_url += f'?{request.url.query}'

    body = await request.body()

    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            upstream = await client.request(
                method=request.method,
                url=target_url,
                content=body if body else None,
                headers=clean_headers(request.headers),
            )
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail='Upstream request failed') from exc

    response_headers = clean_headers(upstream.headers)
    return Response(content=upstream.content, status_code=upstream.status_code, headers=response_headers)
