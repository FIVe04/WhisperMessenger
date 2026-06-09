import logging

from fastapi import APIRouter, HTTPException, Query, WebSocket, WebSocketDisconnect, status
from whispre_common.logging import log_event

from .connections import connection_manager
from .security import decode_access_token
from .service import ensure_device_owner

router = APIRouter(prefix='/v1/realtime')
logger = logging.getLogger('realtime-service.websocket')


def extract_bearer_token(websocket: WebSocket) -> str:
    auth_header = websocket.headers.get('authorization', '')
    if not auth_header.lower().startswith('bearer '):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Missing bearer token')
    return auth_header[7:]


@router.websocket('/ws')
async def realtime_ws(websocket: WebSocket, device_id: str = Query(...)) -> None:
    try:
        token = extract_bearer_token(websocket)
        payload = decode_access_token(token)
        current_user_id = str(payload['sub'])
        ensure_device_owner(current_user_id, device_id)
    except HTTPException as exc:
        log_event(
            logger,
            logging.WARNING,
            'websocket_connection_rejected',
            device_id=device_id,
            status=exc.status_code,
            reason=str(exc.detail),
        )
        await websocket.close(code=1008)
        return

    await connection_manager.connect(device_id, websocket)
    await websocket.send_json({'type': 'connected', 'device_id': device_id})

    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect as exc:
        log_event(
            logger,
            logging.INFO,
            'websocket_client_disconnected',
            user_id=current_user_id,
            device_id=device_id,
            close_code=exc.code,
        )
    finally:
        await connection_manager.disconnect(device_id, websocket)
