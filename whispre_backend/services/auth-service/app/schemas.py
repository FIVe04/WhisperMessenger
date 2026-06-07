from datetime import datetime
from base64 import b64decode
from binascii import Error as BinasciiError

from pydantic import BaseModel, EmailStr, Field, field_validator


def validate_base64_bytes(value: str, expected_length: int, field_name: str) -> str:
    try:
        decoded = b64decode(value, validate=True)
    except (BinasciiError, ValueError) as exc:
        raise ValueError(f'{field_name} must be valid base64') from exc
    if len(decoded) != expected_length:
        raise ValueError(f'{field_name} must decode to {expected_length} bytes')
    return value


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
    prekey_id: int = Field(gt=0)
    prekey_pub: str

    @field_validator('prekey_pub')
    @classmethod
    def validate_prekey_pub(cls, value: str) -> str:
        return validate_base64_bytes(value, 32, 'prekey_pub')


class DeviceRegisterRequest(BaseModel):
    device_name: str = Field(min_length=1, max_length=128)
    platform: str
    identity_key_pub: str
    identity_signing_key_pub: str
    signed_prekey_id: int = Field(gt=0)
    signed_prekey_pub: str
    signed_prekey_signature: str
    one_time_prekeys: list[DeviceOneTimePrekey] = Field(min_length=1, max_length=100)

    @field_validator('identity_key_pub', 'identity_signing_key_pub', 'signed_prekey_pub')
    @classmethod
    def validate_public_key(cls, value: str) -> str:
        return validate_base64_bytes(value, 32, 'public key')

    @field_validator('signed_prekey_signature')
    @classmethod
    def validate_signed_prekey_signature(cls, value: str) -> str:
        return validate_base64_bytes(value, 64, 'signed_prekey_signature')


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
