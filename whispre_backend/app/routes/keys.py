# app/routes/keys.py
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from uuid import UUID

from app.auth import get_current_user
from app.database import get_db
from app.models import User, Device, OneTimePreKey
from app.schemas import DeviceResponse

router = APIRouter(prefix="/keys", tags=["keys"])

@router.get("/exchange/{recipient_id}", response_model=list[dict])
def exchange_keys(
    recipient_id: UUID,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    if recipient_id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot exchange keys with yourself")

    recipient = db.query(User).filter(User.id == recipient_id).first()
    if not recipient:
        raise HTTPException(status_code=404, detail="Recipient not found")

    devices = db.query(Device).filter(Device.user_id == recipient_id).all()
    if not devices:
        raise HTTPException(status_code=404, detail="Recipient has no devices")

    key_bundle = []
    for device in devices:
        prekey = (
            db.query(OneTimePreKey)
            .filter(OneTimePreKey.device_id == device.id, OneTimePreKey.used == False)
            .first()
        )

        prekey_value = None
        prekey_id = None

        if prekey:
            prekey_value = prekey.prekey
            prekey_id = prekey.id
            prekey.used = True
            db.commit()
            db.refresh(prekey)

        key_bundle.append({
            "device_id": device.device_id,
            "device_name": device.device_name,
            "identity_key": device.identity_key,
            "signed_prekey": device.signed_prekey,
            "signed_prekey_signature": device.signed_prekey_signature,
            "one_time_prekey_id": str(prekey_id) if prekey_id else None,
            "one_time_prekey": prekey_value,
        })

    return key_bundle
