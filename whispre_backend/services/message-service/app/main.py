import asyncio
import json
import logging
import uuid
from contextlib import asynccontextmanager
from datetime import UTC, datetime

from aiokafka import AIOKafkaProducer
from fastapi import Depends, FastAPI, HTTPException, Path, Query, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from psycopg import errors

from .config import settings
from .db import get_db
from .schemas import AckEnvelopeRequest, EnvelopeResponse, SendBatchResponse, SendEnvelopesBatchRequest
from .security import decode_access_token

SERVICE_NAME = settings.service_name
security = HTTPBearer(auto_error=True)
logger = logging.getLogger(SERVICE_NAME)


@asynccontextmanager
async def lifespan(app: FastAPI):
    producer = AIOKafkaProducer(
        bootstrap_servers=settings.kafka_broker,
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
    )
    while True:
        try:
            await producer.start()
            logger.info('Kafka producer started')
            break
        except Exception as exc:
            logger.warning('Kafka producer start failed: %s. Retrying in 2s', exc)
            await asyncio.sleep(2)
    app.state.kafka_producer = producer
    try:
        yield
    finally:
        await producer.stop()


app = FastAPI(title=f'Whispre {SERVICE_NAME}', lifespan=lifespan)


def require_auth(credentials: HTTPAuthorizationCredentials = Depends(security)) -> str:
    payload = decode_access_token(credentials.credentials)
    return str(payload['sub'])


def ensure_conversation_access(conn, user_id: str, conversation_id: str) -> None:
    row = conn.execute(
        '''
        select 1
        from conversation_participants
        where conversation_id = %s and user_id = %s
        ''',
        (conversation_id, user_id),
    ).fetchone()
    if not row:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='No access to conversation')


def ensure_device_owner(conn, user_id: str, device_id: str) -> None:
    row = conn.execute('select user_id::text as user_id from devices where id = %s', (device_id,)).fetchone()
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Device not found')
    if row['user_id'] != user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Device does not belong to user')


@app.get('/health')
def health() -> dict[str, str]:
    return {'status': 'ok', 'service': SERVICE_NAME}


@app.post('/v1/messages/envelopes:batch', response_model=SendBatchResponse, status_code=status.HTTP_202_ACCEPTED)
async def send_envelopes_batch(
    payload: SendEnvelopesBatchRequest,
    current_user_id: str = Depends(require_auth),
) -> SendBatchResponse:
    accepted = 0
    events: list[dict] = []

    with get_db() as conn:
        sender_device_id = payload.envelopes[0].sender_device_id

        try:
            conn.execute(
                '''
                insert into message_send_requests (id, sender_user_id, sender_device_id, idempotency_key, created_at)
                values (%s, %s, %s, %s, now())
                ''',
                (str(uuid.uuid4()), current_user_id, sender_device_id, payload.idempotency_key),
            )
        except errors.UniqueViolation:
            return SendBatchResponse(accepted=0)

        for env in payload.envelopes:
            if env.sender_user_id != current_user_id:
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Sender mismatch')
            if env.sender_device_id != sender_device_id:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Batch must use one sender device')

            ensure_conversation_access(conn, current_user_id, env.conversation_id)

            result = conn.execute(
                '''
                insert into envelopes (
                  id,
                  conversation_id,
                  sender_user_id,
                  sender_device_id,
                  recipient_user_id,
                  recipient_device_id,
                  ciphertext,
                  header_json,
                  sent_at_client,
                  accepted_at_server
                )
                values (%s, %s, %s, %s, %s, %s, %s, %s::jsonb, %s, now())
                on conflict (id) do nothing
                ''',
                (
                    env.envelope_id,
                    env.conversation_id,
                    env.sender_user_id,
                    env.sender_device_id,
                    env.recipient_user_id,
                    env.recipient_device_id,
                    env.ciphertext,
                    json.dumps(env.header),
                    env.sent_at_client,
                ),
            )
            if result.rowcount > 0:
                accepted += 1
                events.append(
                    {
                        'event': 'message.envelope.accepted.v1',
                        'envelope_id': env.envelope_id,
                        'conversation_id': env.conversation_id,
                        'sender_user_id': env.sender_user_id,
                        'sender_device_id': env.sender_device_id,
                        'recipient_user_id': env.recipient_user_id,
                        'recipient_device_id': env.recipient_device_id,
                        'accepted_at_server': datetime.now(UTC).isoformat(),
                    }
                )

    producer: AIOKafkaProducer = app.state.kafka_producer
    for event in events:
        await producer.send_and_wait(settings.kafka_topic_envelope_accepted, event)

    return SendBatchResponse(accepted=accepted)


@app.get('/v1/messages/envelopes/pending', response_model=list[EnvelopeResponse])
def get_pending_envelopes(
    device_id: str = Query(...),
    limit: int = Query(default=100, ge=1, le=1000),
    current_user_id: str = Depends(require_auth),
) -> list[EnvelopeResponse]:
    with get_db() as conn:
        ensure_device_owner(conn, current_user_id, device_id)
        rows = conn.execute(
            '''
            select
              id::text as envelope_id,
              conversation_id::text as conversation_id,
              sender_user_id::text as sender_user_id,
              sender_device_id::text as sender_device_id,
              recipient_user_id::text as recipient_user_id,
              recipient_device_id::text as recipient_device_id,
              ciphertext,
              header_json as header,
              sent_at_client,
              accepted_at_server,
              delivered_at,
              acked_at
            from envelopes
            where recipient_device_id = %s and acked_at is null
            order by accepted_at_server asc
            limit %s
            ''',
            (device_id, limit),
        ).fetchall()

        conn.execute(
            '''
            update envelopes
            set delivered_at = coalesce(delivered_at, now())
            where recipient_device_id = %s and acked_at is null and delivered_at is null
            ''',
            (device_id,),
        )

    return [EnvelopeResponse(**row) for row in rows]


@app.post('/v1/messages/envelopes/{envelope_id}/ack')
def ack_envelope(
    payload: AckEnvelopeRequest,
    envelope_id: str = Path(...),
    current_user_id: str = Depends(require_auth),
) -> dict[str, str]:
    with get_db() as conn:
        ensure_device_owner(conn, current_user_id, payload.device_id)

        row = conn.execute(
            '''
            select id
            from envelopes
            where id = %s and recipient_device_id = %s
            ''',
            (envelope_id, payload.device_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Envelope not found')

        conn.execute(
            'update envelopes set acked_at = now() where id = %s and acked_at is null',
            (envelope_id,),
        )

    return {'status': 'ok'}


@app.get('/v1/messages/conversations/{conversation_id}', response_model=list[EnvelopeResponse])
def get_conversation_history(
    conversation_id: str = Path(...),
    cursor: str | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    current_user_id: str = Depends(require_auth),
) -> list[EnvelopeResponse]:
    with get_db() as conn:
        ensure_conversation_access(conn, current_user_id, conversation_id)

        params = [conversation_id]
        cursor_sql = ''
        if cursor:
            cursor_sql = 'and accepted_at_server < %s'
            params.append(cursor)
        params.append(limit)

        rows = conn.execute(
            f'''
            select
              id::text as envelope_id,
              conversation_id::text as conversation_id,
              sender_user_id::text as sender_user_id,
              sender_device_id::text as sender_device_id,
              recipient_user_id::text as recipient_user_id,
              recipient_device_id::text as recipient_device_id,
              ciphertext,
              header_json as header,
              sent_at_client,
              accepted_at_server,
              delivered_at,
              acked_at
            from envelopes
            where conversation_id = %s
              {cursor_sql}
            order by accepted_at_server desc
            limit %s
            ''',
            tuple(params),
        ).fetchall()

    return [EnvelopeResponse(**row) for row in rows]
