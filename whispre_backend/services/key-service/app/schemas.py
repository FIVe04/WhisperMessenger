from base64 import b64decode
from binascii import Error as BinasciiError

from pydantic import BaseModel, Field, field_validator


def validate_base64_bytes(value: str, expected_length: int, field_name: str) -> str:
    try:
        decoded = b64decode(value, validate=True)
    except (BinasciiError, ValueError) as exc:
        raise ValueError(f'{field_name} must be valid base64') from exc
    if len(decoded) != expected_length:
        raise ValueError(f'{field_name} must decode to {expected_length} bytes')
    return value


class OneTimePrekey(BaseModel):
    prekey_id: int = Field(gt=0)
    prekey_pub: str

    @field_validator('prekey_pub')
    @classmethod
    def validate_prekey_pub(cls, value: str) -> str:
        return validate_base64_bytes(value, 32, 'prekey_pub')


class KeyBundle(BaseModel):
    device_id: str
    identity_key_pub: str
    identity_signing_key_pub: str
    signed_prekey_id: int
    signed_prekey_pub: str
    signed_prekey_signature: str
    one_time_prekey: OneTimePrekey | None = None


class UpdateDeviceBundleRequest(BaseModel):
    identity_key_pub: str
    identity_signing_key_pub: str
    signed_prekey_id: int = Field(gt=0)
    signed_prekey_pub: str
    signed_prekey_signature: str

    @field_validator('identity_key_pub', 'identity_signing_key_pub', 'signed_prekey_pub')
    @classmethod
    def validate_public_key(cls, value: str) -> str:
        return validate_base64_bytes(value, 32, 'public key')

    @field_validator('signed_prekey_signature')
    @classmethod
    def validate_signed_prekey_signature(cls, value: str) -> str:
        return validate_base64_bytes(value, 64, 'signed_prekey_signature')


class ReplenishOneTimePrekeysRequest(BaseModel):
    one_time_prekeys: list[OneTimePrekey] = Field(default_factory=list, max_length=100)
