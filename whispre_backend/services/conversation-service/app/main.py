import uuid
from datetime import UTC, datetime

from fastapi import Depends, FastAPI, HTTPException, Path, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .config import settings
from .db import get_db
from .schemas import Conversation, CreateDirectConversationRequest, Participant
from .security import decode_access_token

SERVICE_NAME = settings.service_name
security = HTTPBearer(auto_error=True)

app = FastAPI(title=f'Whispre {SERVICE_NAME}')


def require_auth(credentials: HTTPAuthorizationCredentials = Depends(security)) -> str:
    payload = decode_access_token(credentials.credentials)
    return str(payload['sub'])


def ensure_user_exists(conn, user_id: str) -> None:
    row = conn.execute('select id from users where id = %s and deleted_at is null', (user_id,)).fetchone()
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found')


@app.get('/health')
def health() -> dict[str, str]:
    return {'status': 'ok', 'service': SERVICE_NAME}


@app.post('/v1/conversations/direct', response_model=Conversation)
def create_direct_conversation(
    payload: CreateDirectConversationRequest,
    current_user_id: str = Depends(require_auth),
) -> Conversation:
    if payload.peer_user_id == current_user_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Cannot create direct chat with self')

    user_low = min(current_user_id, payload.peer_user_id)
    user_high = max(current_user_id, payload.peer_user_id)

    with get_db() as conn:
        ensure_user_exists(conn, current_user_id)
        ensure_user_exists(conn, payload.peer_user_id)

        existing = conn.execute(
            '''
            select conversation_id::text as conversation_id
            from direct_conversation_pairs
            where user_low = %s and user_high = %s
            ''',
            (user_low, user_high),
        ).fetchone()

        if existing:
            row = conn.execute(
                'select id::text as id, type, created_at from conversations where id = %s',
                (existing['conversation_id'],),
            ).fetchone()
            return Conversation(id=row['id'], type=row['type'], created_at=row['created_at'])

        conversation_id = str(uuid.uuid4())
        now = datetime.now(UTC)
        conn.execute(
            'insert into conversations (id, type, created_by, created_at) values (%s, %s, %s, %s)',
            (conversation_id, 'direct', current_user_id, now),
        )
        conn.execute(
            'insert into conversation_participants (conversation_id, user_id, role, joined_at) values (%s, %s, %s, %s)',
            (conversation_id, current_user_id, 'member', now),
        )
        conn.execute(
            'insert into conversation_participants (conversation_id, user_id, role, joined_at) values (%s, %s, %s, %s)',
            (conversation_id, payload.peer_user_id, 'member', now),
        )
        conn.execute(
            'insert into direct_conversation_pairs (user_low, user_high, conversation_id) values (%s, %s, %s)',
            (user_low, user_high, conversation_id),
        )

    return Conversation(id=conversation_id, type='direct', created_at=now)


@app.get('/v1/conversations', response_model=list[Conversation])
def list_conversations(current_user_id: str = Depends(require_auth)) -> list[Conversation]:
    with get_db() as conn:
        rows = conn.execute(
            '''
            select c.id::text as id, c.type, c.created_at
            from conversations c
            join conversation_participants cp on cp.conversation_id = c.id
            where cp.user_id = %s
            order by c.created_at desc
            ''',
            (current_user_id,),
        ).fetchall()

    return [Conversation(id=row['id'], type=row['type'], created_at=row['created_at']) for row in rows]


@app.get('/v1/conversations/{conversation_id}/participants', response_model=list[Participant])
def list_participants(
    conversation_id: str = Path(...),
    current_user_id: str = Depends(require_auth),
) -> list[Participant]:
    with get_db() as conn:
        access = conn.execute(
            '''
            select 1
            from conversation_participants
            where conversation_id = %s and user_id = %s
            ''',
            (conversation_id, current_user_id),
        ).fetchone()
        if not access:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='No access to conversation')

        rows = conn.execute(
            '''
            select cp.user_id::text as user_id, u.username, cp.role
            from conversation_participants cp
            join users u on u.id = cp.user_id
            where cp.conversation_id = %s
            order by u.username asc
            ''',
            (conversation_id,),
        ).fetchall()

    return [Participant(user_id=row['user_id'], username=row['username'], role=row['role']) for row in rows]
