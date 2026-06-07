from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, Field, field_validator


class Envelope(BaseModel):
    envelope_id: str = Field(min_length=36, max_length=36)
    conversation_id: str = Field(min_length=36, max_length=36)
    sender_user_id: str = Field(min_length=36, max_length=36)
    sender_device_id: str = Field(min_length=36, max_length=36)
    recipient_user_id: str = Field(min_length=36, max_length=36)
    recipient_device_id: str = Field(min_length=36, max_length=36)
    ciphertext: str = Field(min_length=32, max_length=262_144)
    header: dict[str, Any] = Field(default_factory=dict)
    sent_at_client: datetime

    @field_validator(
        'envelope_id',
        'conversation_id',
        'sender_user_id',
        'sender_device_id',
        'recipient_user_id',
        'recipient_device_id',
    )
    @classmethod
    def validate_uuid(cls, value: str) -> str:
        UUID(value)
        return value

    @field_validator('ciphertext')
    @classmethod
    def validate_ciphertext(cls, value: str) -> str:
        if not value.startswith('e2e1:'):
            raise ValueError('ciphertext must use e2e1 envelope prefix')
        return value

    @field_validator('header')
    @classmethod
    def validate_header(cls, value: dict[str, Any]) -> dict[str, Any]:
        required = {'ratchet_pub', 'pn', 'n'}
        missing = required.difference(value)
        if missing:
            raise ValueError(f'missing header fields: {", ".join(sorted(missing))}')

        protocol_version = value.get('protocol_version')
        if protocol_version is not None and protocol_version != 2:
            raise ValueError('unsupported protocol_version')

        if protocol_version == 2:
            if not value.get('sender_ephemeral_pub'):
                raise ValueError('sender_ephemeral_pub is required for protocol_version 2')
            if value.get('signed_prekey_id') is None:
                raise ValueError('signed_prekey_id is required for protocol_version 2')

        return value


class SendEnvelopesBatchRequest(BaseModel):
    idempotency_key: str = Field(min_length=1, max_length=256)
    envelopes: list[Envelope] = Field(min_length=1, max_length=100)


class AckEnvelopeRequest(BaseModel):
    device_id: str = Field(min_length=36, max_length=36)

    @field_validator('device_id')
    @classmethod
    def validate_device_id(cls, value: str) -> str:
        UUID(value)
        return value


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
