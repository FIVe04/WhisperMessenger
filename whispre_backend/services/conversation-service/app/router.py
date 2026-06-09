from fastapi import APIRouter, Depends, Path

from .dependencies import require_auth
from .schemas import Conversation, CreateDirectConversationRequest, Participant
from .service import (
    create_direct_conversation,
    list_conversation_participants,
    list_user_conversations,
)

router = APIRouter(prefix='/v1/conversations')


@router.post('/direct', response_model=Conversation)
def create_direct(
    payload: CreateDirectConversationRequest,
    current_user_id: str = Depends(require_auth),
) -> Conversation:
    return create_direct_conversation(current_user_id, payload.peer_user_id)


@router.get('', response_model=list[Conversation])
def list_conversations(current_user_id: str = Depends(require_auth)) -> list[Conversation]:
    return list_user_conversations(current_user_id)


@router.get('/{conversation_id}/participants', response_model=list[Participant])
def list_participants(
    conversation_id: str = Path(...),
    current_user_id: str = Depends(require_auth),
) -> list[Participant]:
    return list_conversation_participants(conversation_id, current_user_id)
