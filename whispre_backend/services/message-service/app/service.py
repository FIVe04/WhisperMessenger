import logging
import uuid
from datetime import UTC, datetime

from fastapi import HTTPException, status
from sqlalchemy import func, select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session
from whispre_common.logging import log_event
from whispre_common.models import (
    ConversationParticipant,
    Device,
    Envelope,
    MessageSendRequest,
)

from .db import get_db
from .schemas import EnvelopeResponse, SendBatchResponse, SendEnvelopesBatchRequest

logger = logging.getLogger('message-service.domain')


def ensure_conversation_access(session: Session, user_id: str, conversation_id: str) -> None:
    participant = session.get(ConversationParticipant, (conversation_id, user_id))
    if participant is None:
        log_event(
            logger,
            logging.WARNING,
            'message_access_rejected',
            user_id=user_id,
            conversation_id=conversation_id,
            reason='not_conversation_participant',
        )
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='No access to conversation')


def ensure_device_owner(session: Session, user_id: str, device_id: str) -> None:
    device = session.get(Device, device_id)
    if device is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Device not found')
    if device.user_id != user_id:
        log_event(
            logger,
            logging.WARNING,
            'message_device_access_rejected',
            user_id=user_id,
            device_id=device_id,
            reason='device_owner_mismatch',
        )
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Device does not belong to user')


def ensure_envelope_route_allowed(
    session: Session,
    *,
    conversation_id: str,
    sender_user_id: str,
    sender_device_id: str,
    recipient_user_id: str,
    recipient_device_id: str,
) -> None:
    participant_ids = set(
        session.scalars(
            select(ConversationParticipant.user_id).where(
                ConversationParticipant.conversation_id == conversation_id,
                ConversationParticipant.user_id.in_([sender_user_id, recipient_user_id]),
            )
        ).all()
    )
    if sender_user_id not in participant_ids:
        log_event(
            logger,
            logging.WARNING,
            'message_route_rejected',
            conversation_id=conversation_id,
            sender_user_id=sender_user_id,
            recipient_user_id=recipient_user_id,
            reason='sender_not_participant',
        )
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Sender has no access to conversation')
    if recipient_user_id not in participant_ids:
        log_event(
            logger,
            logging.WARNING,
            'message_route_rejected',
            conversation_id=conversation_id,
            sender_user_id=sender_user_id,
            recipient_user_id=recipient_user_id,
            reason='recipient_not_participant',
        )
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Recipient has no access to conversation')

    device_owners = dict(
        session.execute(
            select(Device.id, Device.user_id).where(
                Device.id.in_([sender_device_id, recipient_device_id]),
                Device.is_active.is_(True),
            )
        ).all()
    )
    if device_owners.get(sender_device_id) != sender_user_id:
        log_event(
            logger,
            logging.WARNING,
            'message_route_rejected',
            conversation_id=conversation_id,
            sender_device_id=sender_device_id,
            reason='sender_device_mismatch',
        )
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Sender device does not belong to sender')
    if device_owners.get(recipient_device_id) != recipient_user_id:
        log_event(
            logger,
            logging.WARNING,
            'message_route_rejected',
            conversation_id=conversation_id,
            recipient_device_id=recipient_device_id,
            reason='recipient_device_mismatch',
        )
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Recipient device does not belong to recipient')


def _envelope_response(envelope: Envelope) -> EnvelopeResponse:
    return EnvelopeResponse(
        envelope_id=envelope.id,
        conversation_id=envelope.conversation_id,
        sender_user_id=envelope.sender_user_id,
        sender_device_id=envelope.sender_device_id,
        recipient_user_id=envelope.recipient_user_id,
        recipient_device_id=envelope.recipient_device_id,
        ciphertext=envelope.ciphertext,
        header=envelope.header_json,
        sent_at_client=envelope.sent_at_client,
        accepted_at_server=envelope.accepted_at_server,
        delivered_at=envelope.delivered_at,
        acked_at=envelope.acked_at,
    )


def persist_envelope_batch(
    payload: SendEnvelopesBatchRequest,
    current_user_id: str,
) -> tuple[SendBatchResponse, list[dict]]:
    accepted = 0
    events: list[dict] = []
    sender_device_id = payload.envelopes[0].sender_device_id

    with get_db() as session:
        send_request_id = session.scalar(
            insert(MessageSendRequest)
            .values(
                id=str(uuid.uuid4()),
                sender_user_id=current_user_id,
                sender_device_id=sender_device_id,
                idempotency_key=payload.idempotency_key,
                created_at=datetime.now(UTC),
            )
            .on_conflict_do_nothing(
                index_elements=[
                    MessageSendRequest.sender_device_id,
                    MessageSendRequest.idempotency_key,
                ]
            )
            .returning(MessageSendRequest.id)
        )
        if send_request_id is None:
            log_event(
                logger,
                logging.INFO,
                'message_batch_deduplicated',
                user_id=current_user_id,
                sender_device_id=sender_device_id,
                envelope_count=len(payload.envelopes),
            )
            return SendBatchResponse(accepted=0), []

        for envelope in payload.envelopes:
            if envelope.sender_user_id != current_user_id:
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Sender mismatch')
            if envelope.sender_device_id != sender_device_id:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Batch must use one sender device')

            ensure_envelope_route_allowed(
                session,
                conversation_id=envelope.conversation_id,
                sender_user_id=envelope.sender_user_id,
                sender_device_id=envelope.sender_device_id,
                recipient_user_id=envelope.recipient_user_id,
                recipient_device_id=envelope.recipient_device_id,
            )

            accepted_at = datetime.now(UTC)
            inserted_envelope_id = session.scalar(
                insert(Envelope)
                .values(
                    id=envelope.envelope_id,
                    conversation_id=envelope.conversation_id,
                    sender_user_id=envelope.sender_user_id,
                    sender_device_id=envelope.sender_device_id,
                    recipient_user_id=envelope.recipient_user_id,
                    recipient_device_id=envelope.recipient_device_id,
                    ciphertext=envelope.ciphertext,
                    header_json=envelope.header,
                    sent_at_client=envelope.sent_at_client,
                    accepted_at_server=accepted_at,
                )
                .on_conflict_do_nothing(index_elements=[Envelope.id])
                .returning(Envelope.id)
            )
            if inserted_envelope_id is not None:
                accepted += 1
                events.append(
                    {
                        'event': 'message.envelope.accepted.v1',
                        'envelope_id': envelope.envelope_id,
                        'conversation_id': envelope.conversation_id,
                        'sender_user_id': envelope.sender_user_id,
                        'sender_device_id': envelope.sender_device_id,
                        'recipient_user_id': envelope.recipient_user_id,
                        'recipient_device_id': envelope.recipient_device_id,
                        'accepted_at_server': accepted_at.isoformat(),
                    }
                )

    log_event(
        logger,
        logging.INFO,
        'message_batch_accepted',
        user_id=current_user_id,
        sender_device_id=sender_device_id,
        requested=len(payload.envelopes),
        accepted=accepted,
    )
    return SendBatchResponse(accepted=accepted), events


def get_pending_for_device(user_id: str, device_id: str, limit: int) -> list[EnvelopeResponse]:
    with get_db() as session:
        ensure_device_owner(session, user_id, device_id)
        envelopes = session.scalars(
            select(Envelope)
            .where(
                Envelope.recipient_device_id == device_id,
                Envelope.acked_at.is_(None),
            )
            .order_by(Envelope.accepted_at_server)
            .limit(limit)
        ).all()

        session.execute(
            update(Envelope)
            .where(
                Envelope.recipient_device_id == device_id,
                Envelope.acked_at.is_(None),
                Envelope.delivered_at.is_(None),
            )
            .values(delivered_at=func.now())
        )
        responses = [_envelope_response(envelope) for envelope in envelopes]

    log_event(
        logger,
        logging.INFO,
        'pending_envelopes_fetched',
        user_id=user_id,
        device_id=device_id,
        envelope_count=len(responses),
    )
    return responses


def acknowledge_envelope(user_id: str, device_id: str, envelope_id: str) -> None:
    with get_db() as session:
        ensure_device_owner(session, user_id, device_id)
        envelope = session.scalar(
            select(Envelope).where(
                Envelope.id == envelope_id,
                Envelope.recipient_device_id == device_id,
            )
        )
        if envelope is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Envelope not found')
        if envelope.acked_at is None:
            envelope.acked_at = datetime.now(UTC)

    log_event(
        logger,
        logging.INFO,
        'envelope_acknowledged',
        user_id=user_id,
        device_id=device_id,
        envelope_id=envelope_id,
    )


def _parse_cursor(cursor: str) -> datetime:
    try:
        return datetime.fromisoformat(cursor.replace('Z', '+00:00'))
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Invalid cursor') from exc


def get_conversation_envelopes(
    user_id: str,
    conversation_id: str,
    cursor: str | None,
    limit: int,
) -> list[EnvelopeResponse]:
    with get_db() as session:
        ensure_conversation_access(session, user_id, conversation_id)

        query = select(Envelope).where(Envelope.conversation_id == conversation_id)
        if cursor is not None:
            query = query.where(Envelope.accepted_at_server < _parse_cursor(cursor))

        envelopes = session.scalars(
            query.order_by(Envelope.accepted_at_server.desc()).limit(limit)
        ).all()
        responses = [_envelope_response(envelope) for envelope in envelopes]

    return responses
