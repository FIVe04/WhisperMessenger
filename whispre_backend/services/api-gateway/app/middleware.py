import logging

from fastapi import HTTPException, Request, status
from fastapi.responses import JSONResponse
from whispre_common.auth import decode_token
from whispre_common.logging import bind_user_id, log_event

from .config import settings
from .rate_limit import InMemoryRateLimiter

AUTH_BYPASS_PREFIXES = (
    '/v1/auth/',
    '/health',
)

rate_limiter = InMemoryRateLimiter(settings.rate_limit_requests_per_minute)
logger = logging.getLogger('api-gateway.security')


def is_auth_bypassed(path: str) -> bool:
    return any(path.startswith(prefix) for prefix in AUTH_BYPASS_PREFIXES)


def extract_client_id(request: Request) -> str:
    forwarded_for = request.headers.get('x-forwarded-for')
    if forwarded_for:
        return forwarded_for.split(',')[0].strip()
    if request.client:
        return request.client.host
    return 'unknown'


def validate_access_token(auth_header: str) -> str:
    if not auth_header.lower().startswith('bearer '):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Missing bearer token')

    payload = decode_token(
        auth_header[7:],
        secret=settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
        expected_type='access',
    )
    return str(payload['sub'])


async def auth_and_rate_middleware(request: Request, call_next):
    path = request.url.path

    if path.startswith('/v1/'):
        client_id = extract_client_id(request)
        if not await rate_limiter.allow(client_id):
            log_event(
                logger,
                logging.WARNING,
                'gateway_rate_limit_rejected',
                path=path,
                client_id=client_id,
            )
            return JSONResponse(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                content={'detail': 'Rate limit exceeded'},
            )

        if not is_auth_bypassed(path):
            auth_header = request.headers.get('authorization', '')
            try:
                user_id = validate_access_token(auth_header)
                bind_user_id(user_id)
            except HTTPException as exc:
                log_event(
                    logger,
                    logging.WARNING,
                    'gateway_auth_rejected',
                    path=path,
                    reason=str(exc.detail),
                )
                return JSONResponse(status_code=exc.status_code, content={'detail': exc.detail})

    return await call_next(request)
