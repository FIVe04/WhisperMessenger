from datetime import datetime

from pydantic import BaseModel


class PendingNotification(BaseModel):
    notification_id: str
    type: str
    envelope_id: str
    conversation_id: str
    sender_user_id: str
    recipient_device_id: str
    created_at: datetime
