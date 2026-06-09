import logging
import time

import httpx
from fastapi import APIRouter, HTTPException, Request, Response, status
from whispre_common.logging import log_event

from .routing import clean_headers, pick_target

router = APIRouter()
logger = logging.getLogger('api-gateway.proxy')


@router.api_route('/v1/{path:path}', methods=['GET', 'POST', 'PUT', 'PATCH', 'DELETE'])
async def proxy_v1(path: str, request: Request) -> Response:
    full_path = f'/v1/{path}'
    target = pick_target(full_path)
    target_url = f'{target}{full_path}'
    if request.url.query:
        target_url += f'?{request.url.query}'

    body = await request.body()
    started_at = time.perf_counter()

    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            upstream = await client.request(
                method=request.method,
                url=target_url,
                content=body if body else None,
                headers=clean_headers(request.headers),
            )
    except httpx.HTTPError as exc:
        log_event(
            logger,
            logging.ERROR,
            'gateway_upstream_failed',
            method=request.method,
            path=full_path,
            upstream=target,
            duration_ms=round((time.perf_counter() - started_at) * 1000, 2),
            exc_info=True,
        )
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail='Upstream request failed') from exc

    log_event(
        logger,
        logging.INFO if upstream.status_code < 400 else logging.WARNING,
        'gateway_upstream_completed',
        method=request.method,
        path=full_path,
        upstream=target,
        upstream_status=upstream.status_code,
        duration_ms=round((time.perf_counter() - started_at) * 1000, 2),
    )
    return Response(
        content=upstream.content,
        status_code=upstream.status_code,
        headers=clean_headers(upstream.headers),
    )
