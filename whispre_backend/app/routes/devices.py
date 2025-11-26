from datetime import datetime
from typing import List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from app.auth import get_current_user
from app.database import get_db
from app.models import Device, OneTimePreKey
from app.schemas import DeviceCreate, DeviceResponse, OneTimePreKeyResponse
from sqlalchemy.orm import Session

router = APIRouter(prefix="/devices", tags=["devices"])


@router.post("/register", response_model=DeviceResponse)
def register_or_get_device(
    device_data: DeviceCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    existing_device = db.query(Device).filter(
        Device.user_id == current_user.id,
        Device.device_id == device_data.device_id
    ).first()

    if existing_device:
        return existing_device  # просто вернуть, не ошибка

    new_device = Device(
        user_id=current_user.id,
        device_id=device_data.device_id,
        device_name=device_data.device_name,
        identity_key=device_data.identity_key,
        signed_prekey=device_data.signed_prekey,
        signed_prekey_signature=device_data.signed_prekey_signature,
    )
    db.add(new_device)
    db.flush()

    for prekey in device_data.one_time_prekeys:
        otp = OneTimePreKey(device_id=new_device.id, prekey=prekey)
        db.add(otp)

    db.commit()
    db.refresh(new_device)
    return new_device


@router.get("/me", response_model=list[DeviceResponse])
def get_my_devices(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    devices = db.query(Device).filter(Device.user_id == current_user.id).all()
    return devices


@router.get("/user/{user_id}", response_model=list[DeviceResponse])
def get_user_devices(
    user_id: UUID,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    print(user_id)
    devices = db.query(Device).filter(Device.user_id == user_id).all()

    if not devices:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User has no registered devices"
        )
    return devices

@router.delete("/{device_id}")
def delete_device(
    device_id: UUID,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    device = db.query(Device).filter(
        Device.id == device_id,
        Device.user_id == current_user.id
    ).first()

    if not device:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Device not found or does not belong to this user"
        )

    db.delete(device)
    db.commit()
    return {"detail": "Device deleted"}


@router.post("/{device_id}/seen")
def update_last_seen(
        device_id: UUID,
        db: Session = Depends(get_db),
        current_user=Depends(get_current_user),
):
    device = db.query(Device).filter(
        Device.id == device_id, Device.user_id == current_user.id
    ).first()

    if not device:
        raise HTTPException(status_code=404, detail="Device not found")

    device.last_seen = datetime.now()
    db.commit()
    return {"detail": "Updated"}


@router.get("/{device_id}/prekey", response_model=OneTimePreKeyResponse)
def get_prekey(
    device_id: UUID,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    device = db.query(Device).filter(
        Device.id == device_id
    ).first()

    if not device:
        raise HTTPException(status_code=404, detail="Device not found")

    prekey = db.query(OneTimePreKey).filter(
        OneTimePreKey.device_id == device_id,
        OneTimePreKey.used == False
    ).first()

    if not prekey:
        raise HTTPException(
            status_code=404,
            detail="No available prekeys"
        )

    prekey.used = True
    db.commit()
    db.refresh(prekey)
    return prekey
