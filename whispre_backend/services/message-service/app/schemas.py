from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field


class Envelope(BaseModel):
    envelope_id: str
    conversation_id: str
    sender_user_id: str
    sender_device_id: str
    recipient_user_id: str
    recipient_device_id: str
    ciphertext: str
    header: dict[str, Any]
    sent_at_client: datetime


class SendEnvelopesBatchRequest(BaseModel):
    idempotency_key: str = Field(min_length=1, max_length=256)
    envelopes: list[Envelope] = Field(min_length=1)


class AckEnvelopeRequest(BaseModel):
    device_id: str


class SendBatchResponse(BaseModel):
    accepted: int


class EnvelopeResponse(BaseModel):
    envelope_id: str
    conversation_id: str
    sender_user_id: str
    sender_device_id: str
    recipient_user_id: str
    recipient_device_id: str
    ciphertext: str
    header: dict[str, Any]
    sent_at_client: datetime
    accepted_at_server: datetime
    delivered_at: datetime | None = None
    acked_at: datetime | None = None
