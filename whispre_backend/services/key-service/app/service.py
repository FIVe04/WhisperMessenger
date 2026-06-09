import logging
from datetime import UTC, datetime

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session
from whispre_common.logging import log_event
from whispre_common.models import Device, DeviceKeyBundle, OneTimePrekey

from .db import get_db
from .schemas import KeyBundle, ReplenishOneTimePrekeysRequest, UpdateDeviceBundleRequest

logger = logging.getLogger('key-service.domain')


def ensure_device_owner(session: Session, user_id: str, device_id: str) -> Device:
    device = session.get(Device, device_id)
    if device is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Device not found')
    if device.user_id != user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Device does not belong to user')
    return device


def _key_bundle(device: Device, bundle: DeviceKeyBundle) -> KeyBundle:
    return KeyBundle(
        device_id=device.id,
        identity_key_pub=bundle.identity_key_pub,
        identity_signing_key_pub=bundle.identity_signing_key_pub,
        signed_prekey_id=bundle.signed_prekey_id,
        signed_prekey_pub=bundle.signed_prekey_pub,
        signed_prekey_signature=bundle.signed_prekey_signature,
    )


def get_user_key_bundles(user_id: str) -> list[KeyBundle]:
    with get_db() as session:
        rows = session.execute(
            select(Device, DeviceKeyBundle)
            .join(DeviceKeyBundle, DeviceKeyBundle.device_id == Device.id)
            .where(
                Device.user_id == user_id,
                Device.is_active.is_(True),
            )
            .order_by(func.coalesce(Device.last_seen_at, Device.created_at).desc())
        ).all()

    return [_key_bundle(device, bundle) for device, bundle in rows]


def claim_user_one_time_prekey(user_id: str, device_id: str | None) -> KeyBundle:
    with get_db() as session:
        bundle_query = (
            select(Device, DeviceKeyBundle)
            .join(DeviceKeyBundle, DeviceKeyBundle.device_id == Device.id)
            .where(
                Device.user_id == user_id,
                Device.is_active.is_(True),
            )
            .order_by(func.coalesce(Device.last_seen_at, Device.created_at).desc())
            .limit(1)
        )
        if device_id is not None:
            bundle_query = bundle_query.where(Device.id == device_id)

        row = session.execute(bundle_query).first()
        if row is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Bundle not found')

        device, bundle = row
        prekey = session.scalar(
            select(OneTimePrekey)
            .where(
                OneTimePrekey.device_id == device.id,
                OneTimePrekey.is_claimed.is_(False),
            )
            .order_by(OneTimePrekey.created_at)
            .limit(1)
            .with_for_update(skip_locked=True)
        )
        if prekey is None:
            log_event(
                logger,
                logging.WARNING,
                'one_time_prekey_claim_rejected',
                target_user_id=user_id,
                device_id=device.id,
                reason='prekeys_exhausted',
            )
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='No one-time prekeys available')

        prekey.is_claimed = True
        prekey.claimed_at = datetime.now(UTC)
        result = KeyBundle(
            device_id=device.id,
            identity_key_pub=bundle.identity_key_pub,
            identity_signing_key_pub=bundle.identity_signing_key_pub,
            signed_prekey_id=bundle.signed_prekey_id,
            signed_prekey_pub=bundle.signed_prekey_pub,
            signed_prekey_signature=bundle.signed_prekey_signature,
            one_time_prekey={
                'prekey_id': prekey.prekey_id,
                'prekey_pub': prekey.prekey_pub,
            },
        )

    log_event(
        logger,
        logging.INFO,
        'one_time_prekey_claimed',
        target_user_id=user_id,
        device_id=device.id,
        prekey_id=prekey.prekey_id,
    )
    return result


def update_bundle(
    user_id: str,
    device_id: str,
    payload: UpdateDeviceBundleRequest,
) -> None:
    with get_db() as session:
        ensure_device_owner(session, user_id, device_id)
        statement = insert(DeviceKeyBundle).values(
            device_id=device_id,
            identity_key_pub=payload.identity_key_pub,
            identity_signing_key_pub=payload.identity_signing_key_pub,
            signed_prekey_id=payload.signed_prekey_id,
            signed_prekey_pub=payload.signed_prekey_pub,
            signed_prekey_signature=payload.signed_prekey_signature,
            updated_at=datetime.now(UTC),
        )
        session.execute(
            statement.on_conflict_do_update(
                index_elements=[DeviceKeyBundle.device_id],
                set_={
                    'identity_key_pub': statement.excluded.identity_key_pub,
                    'identity_signing_key_pub': statement.excluded.identity_signing_key_pub,
                    'signed_prekey_id': statement.excluded.signed_prekey_id,
                    'signed_prekey_pub': statement.excluded.signed_prekey_pub,
                    'signed_prekey_signature': statement.excluded.signed_prekey_signature,
                    'updated_at': statement.excluded.updated_at,
                },
            )
        )

    log_event(
        logger,
        logging.INFO,
        'device_key_bundle_updated',
        user_id=user_id,
        device_id=device_id,
        signed_prekey_id=payload.signed_prekey_id,
    )


def replenish_prekeys(
    user_id: str,
    device_id: str,
    payload: ReplenishOneTimePrekeysRequest,
) -> int:
    with get_db() as session:
        ensure_device_owner(session, user_id, device_id)

        inserted = 0
        for prekey in payload.one_time_prekeys:
            inserted_prekey_id = session.scalar(
                insert(OneTimePrekey)
                .values(
                    device_id=device_id,
                    prekey_id=prekey.prekey_id,
                    prekey_pub=prekey.prekey_pub,
                    is_claimed=False,
                    created_at=datetime.now(UTC),
                )
                .on_conflict_do_nothing(
                    index_elements=[OneTimePrekey.device_id, OneTimePrekey.prekey_id]
                )
                .returning(OneTimePrekey.id)
            )
            if inserted_prekey_id is not None:
                inserted += 1

    log_event(
        logger,
        logging.INFO,
        'one_time_prekeys_replenished',
        user_id=user_id,
        device_id=device_id,
        requested=len(payload.one_time_prekeys),
        inserted=inserted,
    )
    return inserted
