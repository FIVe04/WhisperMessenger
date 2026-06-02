from fastapi import Depends, FastAPI, HTTPException, Query, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .config import settings
from .db import get_db
from .schemas import UserSummary
from .security import decode_access_token

SERVICE_NAME = settings.service_name
security = HTTPBearer(auto_error=True)

app = FastAPI(title=f'Whispre {SERVICE_NAME}')


def require_auth(credentials: HTTPAuthorizationCredentials = Depends(security)) -> str:
    payload = decode_access_token(credentials.credentials)
    return str(payload['sub'])


@app.get('/health')
def health() -> dict[str, str]:
    return {'status': 'ok', 'service': SERVICE_NAME}


@app.get('/v1/users/search', response_model=list[UserSummary])
def search_users(
    username: str = Query(min_length=1, max_length=64),
    _current_user_id: str = Depends(require_auth),
) -> list[UserSummary]:
    pattern = f"%{username.lower()}%"
    with get_db() as conn:
        rows = conn.execute(
            '''
            select id::text as id, username
            from users
            where deleted_at is null
              and lower(username) like %s
            order by username asc
            limit 20
            ''',
            (pattern,),
        ).fetchall()
    return [UserSummary(id=row['id'], username=row['username']) for row in rows]


@app.get('/v1/users/me', response_model=UserSummary)
def me(current_user_id: str = Depends(require_auth)) -> UserSummary:
    with get_db() as conn:
        row = conn.execute(
            '''
            select id::text as id, username
            from users
            where id = %s and deleted_at is null
            ''',
            (current_user_id,),
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found')
    return UserSummary(id=row['id'], username=row['username'])
