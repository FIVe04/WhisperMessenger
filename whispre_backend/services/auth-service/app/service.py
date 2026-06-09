import logging
import uuid
from datetime import UTC, datetime

from fastapi import HTTPException, status
from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.exc import IntegrityError
from whispre_common.logging import log_event
from whispre_common.models import Device, DeviceKeyBundle, OneTimePrekey, RefreshToken, User

from .db import get_db
from .schemas import (
    AuthTokens,
    DeviceRegisterRequest,
    DeviceRegisterResponse,
    LoginRequest,
    RegisterRequest,
)
from .security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    hash_token,
    verify_password,
)

logger = logging.getLogger('auth-service.domain')


def issue_tokens(user_id: str, device_id: str | None) -> AuthTokens:
    access_token = create_access_token(user_id)
    refresh_token, refresh_jti, refresh_exp = create_refresh_token(user_id)

    with get_db() as session:
        session.add(
            RefreshToken(
                id=refresh_jti,
                user_id=user_id,
                device_id=device_id,
                token_hash=hash_token(refresh_token),
                expires_at=refresh_exp,
            )
        )

    return AuthTokens(access_token=access_token, refresh_token=refresh_token)


def register_user(payload: RegisterRequest) -> AuthTokens:
    user_id = str(uuid.uuid4())

    try:
        with get_db() as session:
            session.add(
                User(
                    id=user_id,
                    username=payload.username,
                    email=payload.email.lower(),
                    password_hash=hash_password(payload.password),
                    created_at=datetime.now(UTC),
                )
            )
            session.flush()
    except IntegrityError as exc:
        log_event(logger, logging.WARNING, 'auth_registration_rejected', reason='user_already_exists')
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='User already exists') from exc

    log_event(logger, logging.INFO, 'auth_user_registered', user_id=user_id)
    return issue_tokens(user_id=user_id, device_id=None)


def login_user(payload: LoginRequest) -> AuthTokens:
    with get_db() as session:
        user = session.scalar(
            select(User).where(
                User.email == payload.email.lower(),
                User.deleted_at.is_(None),
            )
        )

    if user is None or not verify_password(payload.password, user.password_hash):
        log_event(logger, logging.WARNING, 'auth_login_rejected', reason='invalid_credentials')
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid credentials')

    log_event(logger, logging.INFO, 'auth_login_succeeded', user_id=user.id)
    return issue_tokens(user_id=user.id, device_id=None)


def refresh_session(refresh_token: str) -> AuthTokens:
    refresh_payload = decode_token(refresh_token, expected_type='refresh')
    user_id = str(refresh_payload['sub'])
    jti = str(refresh_payload['jti'])

    with get_db() as session:
        token_record = session.get(RefreshToken, jti)
        if token_record is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Refresh token is invalid')
        if token_record.revoked_at is not None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Refresh token is revoked')
        if token_record.expires_at < datetime.now(UTC):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Refresh token expired')
        if token_record.token_hash != hash_token(refresh_token):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Refresh token is invalid')
        if token_record.user_id != user_id:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Refresh token is invalid')

        token_record.revoked_at = datetime.now(UTC)
        device_id = token_record.device_id

    log_event(logger, logging.INFO, 'auth_session_refreshed', user_id=user_id, device_id=device_id)
    return issue_tokens(user_id=user_id, device_id=device_id)


def logout_session(refresh_token: str) -> None:
    token_payload = decode_token(refresh_token, expected_type='refresh')
    jti = str(token_payload['jti'])

    with get_db() as session:
        session.execute(
            update(RefreshToken)
            .where(RefreshToken.id == jti)
            .values(revoked_at=datetime.now(UTC))
        )

    log_event(logger, logging.INFO, 'auth_session_logged_out', user_id=str(token_payload['sub']))


def register_device_for_user(
    payload: DeviceRegisterRequest,
    user_id: str,
    requested_device_id: str | None,
) -> DeviceRegisterResponse:
    platform = payload.platform.lower()
    if platform not in {'ios', 'android', 'macos', 'web'}:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Unsupported platform')

    effective_device_id = requested_device_id or str(uuid.uuid4())
    now = datetime.now(UTC)

    with get_db() as session:
        existing_device = session.get(Device, effective_device_id)
        was_existing = existing_device is not None

        if existing_device is not None and existing_device.user_id != user_id:
            log_event(
                logger,
                logging.WARNING,
                'device_registration_rejected',
                user_id=user_id,
                device_id=effective_device_id,
                reason='device_owned_by_another_user',
            )
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Device id already belongs to another user')

        other_device_id = session.scalar(
            select(Device.id)
            .where(
                Device.user_id == user_id,
                Device.id != effective_device_id,
                Device.is_active.is_(True),
            )
            .limit(1)
        )
        if other_device_id is not None:
            log_event(
                logger,
                logging.WARNING,
                'device_registration_rejected',
                user_id=user_id,
                device_id=effective_device_id,
                reason='single_device_policy',
            )
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail='Single-device mode: account is already linked to another device',
            )

        if existing_device is None:
            session.add(
                Device(
                    id=effective_device_id,
                    user_id=user_id,
                    name=payload.device_name,
                    platform=platform,
                    is_active=True,
                    last_seen_at=now,
                    created_at=now,
                )
            )
        else:
            existing_device.name = payload.device_name
            existing_device.platform = platform
            existing_device.is_active = True
            existing_device.last_seen_at = now

        session.flush()
        bundle_statement = insert(DeviceKeyBundle).values(
            device_id=effective_device_id,
            identity_key_pub=payload.identity_key_pub,
            identity_signing_key_pub=payload.identity_signing_key_pub,
            signed_prekey_id=payload.signed_prekey_id,
            signed_prekey_pub=payload.signed_prekey_pub,
            signed_prekey_signature=payload.signed_prekey_signature,
            updated_at=now,
        )
        session.execute(
            bundle_statement.on_conflict_do_update(
                index_elements=[DeviceKeyBundle.device_id],
                set_={
                    'identity_key_pub': bundle_statement.excluded.identity_key_pub,
                    'identity_signing_key_pub': bundle_statement.excluded.identity_signing_key_pub,
                    'signed_prekey_id': bundle_statement.excluded.signed_prekey_id,
                    'signed_prekey_pub': bundle_statement.excluded.signed_prekey_pub,
                    'signed_prekey_signature': bundle_statement.excluded.signed_prekey_signature,
                    'updated_at': bundle_statement.excluded.updated_at,
                },
            )
        )

        uploaded = 0
        for prekey in payload.one_time_prekeys:
            inserted_prekey_id = session.scalar(
                insert(OneTimePrekey)
                .values(
                    device_id=effective_device_id,
                    prekey_id=prekey.prekey_id,
                    prekey_pub=prekey.prekey_pub,
                    is_claimed=False,
                    created_at=now,
                )
                .on_conflict_do_nothing(
                    index_elements=[OneTimePrekey.device_id, OneTimePrekey.prekey_id]
                )
                .returning(OneTimePrekey.id)
            )
            if inserted_prekey_id is not None:
                uploaded += 1

    log_event(
        logger,
        logging.INFO,
        'device_registered',
        user_id=user_id,
        device_id=effective_device_id,
        platform=platform,
        registration_type='updated' if was_existing else 'created',
        one_time_prekeys_uploaded=uploaded,
    )
    return DeviceRegisterResponse(device_id=effective_device_id, one_time_prekeys_uploaded=uploaded)
