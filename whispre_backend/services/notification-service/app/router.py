import logging

from fastapi import APIRouter, Depends, HTTPException, Query, status
from whispre_common.logging import log_event

from .dependencies import require_auth
from .queue import notification_queue
from .schemas import PendingNotification
from .service import ensure_device_owner

router = APIRouter(prefix='/v1/notifications')
logger = logging.getLogger('notification-service.domain')


@router.get('/pending', response_model=list[PendingNotification])
async def get_pending_notifications(
    device_id: str = Query(...),
    limit: int = Query(default=100, ge=1, le=1000),
    current_user_id: str = Depends(require_auth),
) -> list[PendingNotification]:
    ensure_device_owner(current_user_id, device_id)
    items = await notification_queue.list_for_device(device_id, limit)
    log_event(
        logger,
        logging.INFO,
        'pending_notifications_fetched',
        user_id=current_user_id,
        device_id=device_id,
        notification_count=len(items),
    )
    return [PendingNotification(**item) for item in items]


@router.post('/{notification_id}/ack')
async def ack_notification(
    notification_id: str,
    device_id: str = Query(...),
    current_user_id: str = Depends(require_auth),
) -> dict[str, str]:
    ensure_device_owner(current_user_id, device_id)
    acknowledged = await notification_queue.ack(device_id, notification_id)
    if not acknowledged:
        log_event(
            logger,
            logging.WARNING,
            'notification_ack_rejected',
            user_id=current_user_id,
            device_id=device_id,
            notification_id=notification_id,
            reason='notification_not_found',
        )
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Notification not found')
    log_event(
        logger,
        logging.INFO,
        'notification_acknowledged',
        user_id=current_user_id,
        device_id=device_id,
        notification_id=notification_id,
    )
    return {'status': 'ok'}
