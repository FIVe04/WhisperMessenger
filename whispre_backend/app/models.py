from sqlalchemy import (
    Column, String, Boolean, DateTime, ForeignKey, Text, LargeBinary, Enum, UniqueConstraint
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import declarative_base, relationship
from sqlalchemy.sql import func
import enum
import uuid
from app.database import Base


class MessageStatus(str, enum.Enum):
    pending = "pending"
    delivered = "delivered"
    read = "read"
    failed = "failed"


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    username = Column(String, unique=True, nullable=False)
    email = Column(String, unique=True, nullable=False)
    password_hash = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    devices = relationship("Device", back_populates="user", cascade="all, delete-orphan")
    messages_sent = relationship("Message", back_populates="sender_user", foreign_keys="Message.sender_user_id")
    messages_received = relationship("Message", back_populates="recipient_user", foreign_keys="Message.recipient_user_id")
    sessions = relationship("Session", back_populates="user", cascade="all, delete-orphan")


class Device(Base):
    __tablename__ = "devices"
    __table_args__ = (UniqueConstraint("user_id", "device_id", name="uq_user_device"),)

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    device_id = Column(String, nullable=False)  # client-supplied identifier
    device_name = Column(String)
    identity_key = Column(Text, nullable=False)
    signed_prekey = Column(Text, nullable=False)
    signed_prekey_signature = Column(Text, nullable=False)
    last_seen = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="devices")
    one_time_prekeys = relationship("OneTimePreKey", back_populates="device", cascade="all, delete-orphan")


class OneTimePreKey(Base):
    __tablename__ = "one_time_prekeys"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    device_id = Column(UUID(as_uuid=True), ForeignKey("devices.id", ondelete="CASCADE"), nullable=False)
    prekey = Column(Text, nullable=False)
    used = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    device = relationship("Device", back_populates="one_time_prekeys")


class Message(Base):
    __tablename__ = "messages"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    sender_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    sender_device_id = Column(String, nullable=False)
    recipient_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    recipient_device_id = Column(String, nullable=False)
    ciphertext = Column(LargeBinary, nullable=False)
    content_type = Column(String, nullable=False)
    status = Column(Enum(MessageStatus), default=MessageStatus.pending)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    delivered_at = Column(DateTime(timezone=True))
    read_at = Column(DateTime(timezone=True))

    sender_user = relationship("User", back_populates="messages_sent", foreign_keys=[sender_user_id])
    recipient_user = relationship("User", back_populates="messages_received", foreign_keys=[recipient_user_id])


class Session(Base):
    __tablename__ = "sessions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    refresh_token_hash = Column(Text, nullable=False)
    device_id = Column(UUID(as_uuid=True), ForeignKey("devices.id"))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    expires_at = Column(DateTime(timezone=True))

    user = relationship("User", back_populates="sessions")
