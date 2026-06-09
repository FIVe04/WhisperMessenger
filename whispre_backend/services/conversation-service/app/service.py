import logging
import uuid
from datetime import UTC, datetime

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session
from whispre_common.logging import log_event
from whispre_common.models import (
    Conversation as ConversationModel,
    ConversationParticipant,
    DirectConversationPair,
    User,
)

from .db import get_db
from .schemas import Conversation, Participant

logger = logging.getLogger('conversation-service.domain')


def ensure_user_exists(session: Session, user_id: str) -> None:
    exists = session.scalar(
        select(User.id).where(
            User.id == user_id,
            User.deleted_at.is_(None),
        )
    )
    if exists is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found')


def create_direct_conversation(current_user_id: str, peer_user_id: str) -> Conversation:
    if peer_user_id == current_user_id:
        log_event(
            logger,
            logging.WARNING,
            'conversation_creation_rejected',
            user_id=current_user_id,
            reason='self_conversation',
        )
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Cannot create direct chat with self')

    user_low = min(current_user_id, peer_user_id)
    user_high = max(current_user_id, peer_user_id)

    with get_db() as session:
        ensure_user_exists(session, current_user_id)
        ensure_user_exists(session, peer_user_id)

        existing_pair = session.get(DirectConversationPair, (user_low, user_high))
        if existing_pair is not None:
            conversation = session.get(ConversationModel, existing_pair.conversation_id)
            if conversation is None:
                raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Conversation pair is invalid')
            log_event(
                logger,
                logging.INFO,
                'conversation_reused',
                conversation_id=conversation.id,
                user_id=current_user_id,
                peer_user_id=peer_user_id,
            )
            return Conversation(
                id=conversation.id,
                type=conversation.type,
                created_at=conversation.created_at,
            )

        conversation_id = str(uuid.uuid4())
        now = datetime.now(UTC)
        session.add_all(
            [
                ConversationModel(
                    id=conversation_id,
                    type='direct',
                    created_by=current_user_id,
                    created_at=now,
                ),
                ConversationParticipant(
                    conversation_id=conversation_id,
                    user_id=current_user_id,
                    role='member',
                    joined_at=now,
                ),
                ConversationParticipant(
                    conversation_id=conversation_id,
                    user_id=peer_user_id,
                    role='member',
                    joined_at=now,
                ),
                DirectConversationPair(
                    user_low=user_low,
                    user_high=user_high,
                    conversation_id=conversation_id,
                ),
            ]
        )

    log_event(
        logger,
        logging.INFO,
        'conversation_created',
        conversation_id=conversation_id,
        user_id=current_user_id,
        peer_user_id=peer_user_id,
        conversation_type='direct',
    )
    return Conversation(id=conversation_id, type='direct', created_at=now)


def list_user_conversations(user_id: str) -> list[Conversation]:
    with get_db() as session:
        conversations = session.scalars(
            select(ConversationModel)
            .join(
                ConversationParticipant,
                ConversationParticipant.conversation_id == ConversationModel.id,
            )
            .where(ConversationParticipant.user_id == user_id)
            .order_by(ConversationModel.created_at.desc())
        ).all()

    return [
        Conversation(id=conversation.id, type=conversation.type, created_at=conversation.created_at)
        for conversation in conversations
    ]


def list_conversation_participants(conversation_id: str, user_id: str) -> list[Participant]:
    with get_db() as session:
        access = session.get(ConversationParticipant, (conversation_id, user_id))
        if access is None:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='No access to conversation')

        rows = session.execute(
            select(
                ConversationParticipant.user_id,
                User.username,
                ConversationParticipant.role,
            )
            .join(User, User.id == ConversationParticipant.user_id)
            .where(ConversationParticipant.conversation_id == conversation_id)
            .order_by(User.username)
        ).all()

    return [
        Participant(user_id=participant_user_id, username=username, role=role)
        for participant_user_id, username, role in rows
    ]
