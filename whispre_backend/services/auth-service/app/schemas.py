from datetime import datetime

from pydantic import BaseModel, EmailStr, Field


class RegisterRequest(BaseModel):
    username: str = Field(min_length=3, max_length=64)
    email: EmailStr
    password: str = Field(min_length=8, max_length=256)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class LogoutRequest(BaseModel):
    refresh_token: str


class DeviceOneTimePrekey(BaseModel):
    prekey_id: int
    prekey_pub: str


class DeviceRegisterRequest(BaseModel):
    device_name: str = Field(min_length=1, max_length=128)
    platform: str
    identity_key_pub: str
    signed_prekey_id: int
    signed_prekey_pub: str
    signed_prekey_signature: str
    one_time_prekeys: list[DeviceOneTimePrekey]


class AuthTokens(BaseModel):
    access_token: str
    refresh_token: str


class DeviceRegisterResponse(BaseModel):
    device_id: str
    one_time_prekeys_uploaded: int


class ErrorResponse(BaseModel):
    code: str
    message: str


class RefreshTokenRecord(BaseModel):
    id: str
    user_id: str
    device_id: str
    token_hash: str
    expires_at: datetime
