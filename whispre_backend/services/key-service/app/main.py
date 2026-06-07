from fastapi import Depends, FastAPI, HTTPException, Path, Query, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .config import settings
from .db import get_db
from .schemas import KeyBundle, ReplenishOneTimePrekeysRequest, UpdateDeviceBundleRequest
from .security import decode_access_token

SERVICE_NAME = settings.service_name
security = HTTPBearer(auto_error=True)

app = FastAPI(title=f'Whispre {SERVICE_NAME}')


def require_auth(credentials: HTTPAuthorizationCredentials = Depends(security)) -> str:
    payload = decode_access_token(credentials.credentials)
    return str(payload['sub'])


def ensure_device_owner(conn, user_id: str, device_id: str) -> None:
    row = conn.execute('select user_id::text as user_id from devices where id = %s', (device_id,)).fetchone()
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Device not found')
    if row['user_id'] != user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Device does not belong to user')


@app.get('/health')
def health() -> dict[str, str]:
    return {'status': 'ok', 'service': SERVICE_NAME}


@app.get('/v1/keys/users/{user_id}/bundles', response_model=list[KeyBundle])
def get_user_bundles(
    user_id: str = Path(...),
    _current_user_id: str = Depends(require_auth),
) -> list[KeyBundle]:
    with get_db() as conn:
        rows = conn.execute(
            '''
            select
              d.id::text as device_id,
              b.identity_key_pub,
              b.identity_signing_key_pub,
              b.signed_prekey_id,
              b.signed_prekey_pub,
              b.signed_prekey_signature
            from devices d
            join device_key_bundles b on b.device_id = d.id
            where d.user_id = %s and d.is_active = true
            order by coalesce(d.last_seen_at, d.created_at) desc
            ''',
            (user_id,),
        ).fetchall()

    return [
        KeyBundle(
            device_id=row['device_id'],
            identity_key_pub=row['identity_key_pub'],
            identity_signing_key_pub=row['identity_signing_key_pub'],
            signed_prekey_id=row['signed_prekey_id'],
            signed_prekey_pub=row['signed_prekey_pub'],
            signed_prekey_signature=row['signed_prekey_signature'],
        )
        for row in rows
    ]


@app.post('/v1/keys/users/{user_id}/one-time-prekey/claim', response_model=KeyBundle)
def claim_one_time_prekey(
    user_id: str = Path(...),
    device_id: str | None = Query(default=None),
    _current_user_id: str = Depends(require_auth),
) -> KeyBundle:
    with get_db() as conn:
        device_filter = 'and d.id = %s' if device_id else ''
        params = (user_id, device_id) if device_id else (user_id,)

        bundle = conn.execute(
            f'''
            select
              d.id::text as device_id,
              b.identity_key_pub,
              b.identity_signing_key_pub,
              b.signed_prekey_id,
              b.signed_prekey_pub,
              b.signed_prekey_signature
            from devices d
            join device_key_bundles b on b.device_id = d.id
            where d.user_id = %s
              and d.is_active = true
              {device_filter}
            order by coalesce(d.last_seen_at, d.created_at) desc
            limit 1
            ''',
            params,
        ).fetchone()

        if not bundle:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Bundle not found')

        prekey = conn.execute(
            '''
            with candidate as (
              select id, prekey_id, prekey_pub
              from one_time_prekeys
              where device_id = %s and is_claimed = false
              order by created_at asc
              limit 1
              for update skip locked
            )
            update one_time_prekeys otp
            set is_claimed = true,
                claimed_at = now()
            from candidate
            where otp.id = candidate.id
            returning candidate.prekey_id, candidate.prekey_pub
            ''',
            (bundle['device_id'],),
        ).fetchone()

    if not prekey:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='No one-time prekeys available')

    return KeyBundle(
        device_id=bundle['device_id'],
        identity_key_pub=bundle['identity_key_pub'],
        identity_signing_key_pub=bundle['identity_signing_key_pub'],
        signed_prekey_id=bundle['signed_prekey_id'],
        signed_prekey_pub=bundle['signed_prekey_pub'],
        signed_prekey_signature=bundle['signed_prekey_signature'],
        one_time_prekey={'prekey_id': prekey['prekey_id'], 'prekey_pub': prekey['prekey_pub']},
    )


@app.put('/v1/keys/devices/{device_id}/bundle')
def update_device_bundle(
    payload: UpdateDeviceBundleRequest,
    device_id: str = Path(...),
    current_user_id: str = Depends(require_auth),
) -> dict[str, str]:
    with get_db() as conn:
        ensure_device_owner(conn, current_user_id, device_id)
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
                device_id,
                payload.identity_key_pub,
                payload.identity_signing_key_pub,
                payload.signed_prekey_id,
                payload.signed_prekey_pub,
                payload.signed_prekey_signature,
            ),
        )
    return {'status': 'ok'}


@app.post('/v1/keys/devices/{device_id}/one-time-prekeys/replenish')
def replenish_one_time_prekeys(
    payload: ReplenishOneTimePrekeysRequest,
    device_id: str = Path(...),
    current_user_id: str = Depends(require_auth),
) -> dict[str, int]:
    with get_db() as conn:
        ensure_device_owner(conn, current_user_id, device_id)

        inserted = 0
        for prekey in payload.one_time_prekeys:
            result = conn.execute(
                '''
                insert into one_time_prekeys (device_id, prekey_id, prekey_pub, is_claimed, created_at)
                values (%s, %s, %s, false, now())
                on conflict (device_id, prekey_id) do nothing
                ''',
                (device_id, prekey.prekey_id, prekey.prekey_pub),
            )
            if result.rowcount > 0:
                inserted += 1

    return {'uploaded': inserted}
