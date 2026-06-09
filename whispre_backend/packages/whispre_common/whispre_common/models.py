from datetime import datetime
from typing import Any

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = 'users'
    __table_args__ = (
        UniqueConstraint('username', name='users_username_key'),
        UniqueConstraint('email', name='users_email_key'),
    )

    id: Mapped[str] = mapped_column(UUID(as_uuid=False), primary_key=True)
    username: Mapped[str] = mapped_column(Text, nullable=False)
    email: Mapped[str] = mapped_column(Text, nullable=False)
    password_hash: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Device(Base):
    __tablename__ = 'devices'
    __table_args__ = (Index('idx_devices_user_name', 'user_id', 'name'),)

    id: Mapped[str] = mapped_column(UUID(as_uuid=False), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey('users.id', ondelete='CASCADE'),
        nullable=False,
    )
    name: Mapped[str] = mapped_column(Text, nullable=False)
    platform: Mapped[str] = mapped_column(Text, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, server_default='true', nullable=False)
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class RefreshToken(Base):
    __tablename__ = 'refresh_tokens'
    __table_args__ = (Index('idx_refresh_tokens_user_device', 'user_id', 'device_id'),)

    id: Mapped[str] = mapped_column(UUID(as_uuid=False), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey('users.id', ondelete='CASCADE'),
        nullable=False,
    )
    device_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey('devices.id', ondelete='CASCADE'),
    )
    token_hash: Mapped[str] = mapped_column(Text, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class DeviceKeyBundle(Base):
    __tablename__ = 'device_key_bundles'

    device_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey('devices.id', ondelete='CASCADE'),
        primary_key=True,
    )
    identity_key_pub: Mapped[str] = mapped_column(Text, nullable=False)
    identity_signing_key_pub: Mapped[str] = mapped_column(Text, server_default='', nullable=False)
    signed_prekey_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    signed_prekey_pub: Mapped[str] = mapped_column(Text, nullable=False)
    signed_prekey_signature: Mapped[str] = mapped_column(Text, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class OneTimePrekey(Base):
    __tablename__ = 'one_time_prekeys'
    __table_args__ = (
        UniqueConstraint(
            'device_id',
            'prekey_id',
            name='one_time_prekeys_device_id_prekey_id_key',
        ),
        Index('idx_one_time_prekeys_claim', 'device_id', 'is_claimed'),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    device_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey('devices.id', ondelete='CASCADE'),
        nullable=False,
    )
    prekey_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    prekey_pub: Mapped[str] = mapped_column(Text, nullable=False)
    is_claimed: Mapped[bool] = mapped_column(Boolean, server_default='false', nullable=False)
    claimed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class Conversation(Base):
    __tablename__ = 'conversations'
    __table_args__ = (
        CheckConstraint("type in ('direct','group')", name='conversations_type_check'),
    )

    id: Mapped[str] = mapped_column(UUID(as_uuid=False), primary_key=True)
    type: Mapped[str] = mapped_column(Text, nullable=False)
    created_by: Mapped[str] = mapped_column(UUID(as_uuid=False), ForeignKey('users.id'), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class ConversationParticipant(Base):
    __tablename__ = 'conversation_participants'

    conversation_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey('conversations.id', ondelete='CASCADE'),
        primary_key=True,
    )
    user_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey('users.id', ondelete='CASCADE'),
        primary_key=True,
    )
    role: Mapped[str] = mapped_column(Text, server_default='member', nullable=False)
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class DirectConversationPair(Base):
    __tablename__ = 'direct_conversation_pairs'
    __table_args__ = (
        UniqueConstraint(
            'conversation_id',
            name='direct_conversation_pairs_conversation_id_key',
        ),
        CheckConstraint(
            'user_low <> user_high',
            name='direct_conversation_pairs_check',
        ),
    )

    user_low: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey('users.id', ondelete='CASCADE'),
        primary_key=True,
    )
    user_high: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey('users.id', ondelete='CASCADE'),
        primary_key=True,
    )
    conversation_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey('conversations.id', ondelete='CASCADE'),
        nullable=False,
    )


class Envelope(Base):
    __tablename__ = 'envelopes'
    __table_args__ = (
        Index('idx_envelopes_pending', 'recipient_device_id', 'acked_at', 'accepted_at_server'),
        Index('idx_envelopes_conversation', 'conversation_id', 'accepted_at_server'),
    )

    id: Mapped[str] = mapped_column(UUID(as_uuid=False), primary_key=True)
    conversation_id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        ForeignKey('conversations.id', ondelete='CASCADE'),
        nullable=False,
    )
    sender_user_id: Mapped[str] = mapped_column(UUID(as_uuid=False), ForeignKey('users.id'), nullable=False)
    sender_device_id: Mapped[str] = mapped_column(UUID(as_uuid=False), ForeignKey('devices.id'), nullable=False)
    recipient_user_id: Mapped[str] = mapped_column(UUID(as_uuid=False), ForeignKey('users.id'), nullable=False)
    recipient_device_id: Mapped[str] = mapped_column(UUID(as_uuid=False), ForeignKey('devices.id'), nullable=False)
    ciphertext: Mapped[str] = mapped_column(Text, nullable=False)
    header_json: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    sent_at_client: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    accepted_at_server: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
    delivered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    acked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class MessageSendRequest(Base):
    __tablename__ = 'message_send_requests'
    __table_args__ = (
        UniqueConstraint(
            'sender_device_id',
            'idempotency_key',
            name='message_send_requests_sender_device_id_idempotency_key_key',
        ),
    )

    id: Mapped[str] = mapped_column(UUID(as_uuid=False), primary_key=True)
    sender_user_id: Mapped[str] = mapped_column(UUID(as_uuid=False), ForeignKey('users.id'), nullable=False)
    sender_device_id: Mapped[str] = mapped_column(UUID(as_uuid=False), ForeignKey('devices.id'), nullable=False)
    idempotency_key: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
