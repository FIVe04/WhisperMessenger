import uuid
from datetime import UTC, datetime

from fastapi import Depends, FastAPI, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from psycopg import errors

from .config import settings
from .db import get_db
from .schemas import (
    AuthTokens,
    DeviceRegisterRequest,
    DeviceRegisterResponse,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
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

SERVICE_NAME = settings.service_name
security = HTTPBearer(auto_error=True)

app = FastAPI(title=f'Whispre {SERVICE_NAME}')


def issue_tokens(user_id: str, device_id: str | None) -> AuthTokens:
    access_token = create_access_token(user_id)
    refresh_token, refresh_jti, refresh_exp = create_refresh_token(user_id)

    with get_db() as conn:
        conn.execute(
            '''
            insert into refresh_tokens (id, user_id, device_id, token_hash, expires_at)
            values (%s, %s, %s, %s, %s)
            ''',
            (refresh_jti, user_id, device_id, hash_token(refresh_token), refresh_exp),
        )

    return AuthTokens(access_token=access_token, refresh_token=refresh_token)


def get_current_user_id(credentials: HTTPAuthorizationCredentials = Depends(security)) -> str:
    payload = decode_token(credentials.credentials, expected_type='access')
    return str(payload['sub'])


@app.get('/health')
def health() -> dict[str, str]:
    return {'status': 'ok', 'service': SERVICE_NAME}


@app.post('/v1/auth/register', response_model=AuthTokens)
def register(payload: RegisterRequest) -> AuthTokens:
    user_id = str(uuid.uuid4())

    with get_db() as conn:
        try:
            conn.execute(
                '''
                insert into users (id, username, email, password_hash, created_at)
                values (%s, %s, %s, %s, %s)
                ''',
                (
                    user_id,
                    payload.username,
                    payload.email.lower(),
                    hash_password(payload.password),
                    datetime.now(UTC),
                ),
            )
        except errors.UniqueViolation as exc:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='User already exists') from exc

    return issue_tokens(user_id=user_id, device_id=None)


@app.post('/v1/auth/login', response_model=AuthTokens)
def login(payload: LoginRequest) -> AuthTokens:
    with get_db() as conn:
        user = conn.execute(
            'select id, password_hash from users where email = %s and deleted_at is null',
            (payload.email.lower(),),
        ).fetchone()

    if not user or not verify_password(payload.password, user['password_hash']):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid credentials')

    return issue_tokens(user_id=str(user['id']), device_id=None)


@app.post('/v1/auth/refresh', response_model=AuthTokens)
def refresh(payload: RefreshRequest) -> AuthTokens:
    refresh_payload = decode_token(payload.refresh_token, expected_type='refresh')
    user_id = str(refresh_payload['sub'])
    jti = str(refresh_payload['jti'])

    with get_db() as conn:
        token_record = conn.execute(
            '''
            select id, user_id, device_id, token_hash, expires_at, revoked_at
            from refresh_tokens
            where id = %s
            ''',
            (jti,),
        ).fetchone()

    if not token_record:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Refresh token is invalid')
    if token_record['revoked_at'] is not None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Refresh token is revoked')
    if token_record['expires_at'] < datetime.now(UTC):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Refresh token expired')
    if token_record['token_hash'] != hash_token(payload.refresh_token):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Refresh token is invalid')
    if str(token_record['user_id']) != user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Refresh token is invalid')

    with get_db() as conn:
        conn.execute('update refresh_tokens set revoked_at = now() where id = %s', (jti,))

    device_id = str(token_record['device_id']) if token_record['device_id'] else None
    return issue_tokens(user_id=user_id, device_id=device_id)


@app.post('/v1/auth/logout')
def logout(payload: LogoutRequest) -> dict[str, str]:
    token_payload = decode_token(payload.refresh_token, expected_type='refresh')
    jti = str(token_payload['jti'])

    with get_db() as conn:
        conn.execute('update refresh_tokens set revoked_at = now() where id = %s', (jti,))

    return {'status': 'ok'}


@app.post('/v1/auth/devices/register', response_model=DeviceRegisterResponse)
def register_device(
    payload: DeviceRegisterRequest,
    user_id: str = Depends(get_current_user_id),
    x_device_id: str | None = Header(default=None, alias='X-Device-Id'),
) -> DeviceRegisterResponse:
    platform = payload.platform.lower()
    if platform not in {'ios', 'android', 'macos', 'web'}:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Unsupported platform')

    requested_device_id = x_device_id or str(uuid.uuid4())
    effective_device_id = requested_device_id

    with get_db() as conn:
        existing_by_id = conn.execute(
            'select user_id::text as user_id from devices where id = %s',
            (requested_device_id,),
        ).fetchone()

        if existing_by_id and existing_by_id['user_id'] != user_id:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Device id already belongs to another user')

        # MVP policy: one account can have only one active device.
        existing_other_device = conn.execute(
            '''
            select id::text as id
            from devices
            where user_id = %s and id <> %s and is_active = true
            limit 1
            ''',
            (user_id, requested_device_id),
        ).fetchone()
        if existing_other_device:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail='Single-device mode: account is already linked to another device',
            )

        if existing_by_id:
            conn.execute(
                '''
                update devices
                set name = %s,
                    platform = %s,
                    is_active = true,
                    last_seen_at = now()
                where id = %s
                ''',
                (payload.device_name, platform, effective_device_id),
            )
        else:
            conn.execute(
                '''
                insert into devices (id, user_id, name, platform, is_active, last_seen_at, created_at)
                values (%s, %s, %s, %s, true, now(), now())
                ''',
                (effective_device_id, user_id, payload.device_name, platform),
            )

        conn.execute(
            '''
            insert into device_key_bundles (
                device_id,
                identity_key_pub,
                identity_signing_key_pub,
                signed_prekey_id,
                signed_prekey_pub,
                signed_prekey_signature,
                updated_at
            )
            values (%s, %s, %s, %s, %s, %s, now())
            on conflict (device_id) do update
            set identity_key_pub = excluded.identity_key_pub,
                identity_signing_key_pub = excluded.identity_signing_key_pub,
                signed_prekey_id = excluded.signed_prekey_id,
                signed_prekey_pub = excluded.signed_prekey_pub,
                signed_prekey_signature = excluded.signed_prekey_signature,
                updated_at = now()
            ''',
            (
                effective_device_id,
                payload.identity_key_pub,
                payload.identity_signing_key_pub,
                payload.signed_prekey_id,
                payload.signed_prekey_pub,
                payload.signed_prekey_signature,
            ),
        )

        uploaded = 0
        for prekey in payload.one_time_prekeys:
            result = conn.execute(
                '''
                insert into one_time_prekeys (device_id, prekey_id, prekey_pub, is_claimed, created_at)
                values (%s, %s, %s, false, now())
                on conflict (device_id, prekey_id) do nothing
                ''',
                (effective_device_id, prekey.prekey_id, prekey.prekey_pub),
            )
            if result.rowcount > 0:
                uploaded += 1

    return DeviceRegisterResponse(device_id=effective_device_id, one_time_prekeys_uploaded=uploaded)
