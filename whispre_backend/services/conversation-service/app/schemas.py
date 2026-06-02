from datetime import datetime

from pydantic import BaseModel


class CreateDirectConversationRequest(BaseModel):
    peer_user_id: str


class Conversation(BaseModel):
    id: str
    type: str
    created_at: datetime


class Participant(BaseModel):
    user_id: str
    username: str
    role: str
