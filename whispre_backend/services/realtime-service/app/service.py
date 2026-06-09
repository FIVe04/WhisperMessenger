from fastapi import HTTPException, status
from whispre_common.models import Device

from .db import get_db


def ensure_device_owner(user_id: str, device_id: str) -> None:
    with get_db() as session:
        device = session.get(Device, device_id)

    if device is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Device not found')
    if device.user_id != user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Device does not belong to user')
