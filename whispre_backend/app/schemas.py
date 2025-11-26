from pydantic import BaseModel, EmailStr, field_validator, ValidationError
from typing import Optional, List
from uuid import UUID
from datetime import datetime
from enum import Enum



class MessageStatus(str, Enum):
    pending = "pending"
    delivered = "delivered"
    read = "read"
    failed = "failed"


class UserBase(BaseModel):
    username: str
    email: EmailStr

    @field_validator("email")
    def email_must_be_valid(cls, v):
        if "@" not in v:
            raise ValueError("Email should inculde @")
        return v


class UserLogin(BaseModel):
    email: EmailStr
    password: str

    @field_validator("email")
    def email_must_be_valid(cls, v):
        if "@" not in v:
            raise ValueError("Email should include @")
        return v


class UserCreate(UserBase):
    password: str


class UserResponse(UserBase):
    id: UUID
    created_at: datetime

    class Config:
        orm_mode = True


class DeviceBase(BaseModel):
    device_id: str
    device_name: Optional[str] = None
    identity_key: str
    signed_prekey: str
    signed_prekey_signature: str


class DeviceCreate(DeviceBase):
    one_time_prekeys: List[str]


class DeviceResponse(DeviceBase):
    id: UUID
    created_at: datetime

    class Config:
        orm_mode = True


class OneTimePreKeyResponse(BaseModel):
    id: UUID
    device_id: UUID
    prekey: str
    used: bool
    created_at: datetime

    class Config:
        orm_mode = True


class MessageBase(BaseModel):
    sender_device_id: str
    recipient_user_id: UUID
    recipient_device_id: str
    ciphertext: bytes
    content_type: str

class MessageCreate(MessageBase):
    pass

class MessageResponse(MessageBase):
    id: UUID
    sender_user_id: UUID
    status: MessageStatus
    created_at: datetime
    delivered_at: Optional[datetime] = None
    read_at: Optional[datetime] = None

    class Config:
        orm_mode = True


class SessionBase(BaseModel):
    device_id: Optional[UUID]

class SessionResponse(SessionBase):
    id: UUID
    user_id: UUID
    created_at: datetime
    expires_at: Optional[datetime] = None

    class Config:
        orm_mode = True


class Token(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class TokenData(BaseModel):
    user_id: Optional[UUID] = None

class FriendOut(BaseModel):
    id: UUID
    username: str

    class Config:
        orm_mode = True


class UserByUsernameRequest(BaseModel):
    username: str
