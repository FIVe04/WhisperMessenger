from pydantic import BaseModel, Field


class OneTimePrekey(BaseModel):
    prekey_id: int
    prekey_pub: str


class KeyBundle(BaseModel):
    device_id: str
    identity_key_pub: str
    signed_prekey_id: int
    signed_prekey_pub: str
    signed_prekey_signature: str
    one_time_prekey: OneTimePrekey | None = None


class UpdateDeviceBundleRequest(BaseModel):
    identity_key_pub: str
    signed_prekey_id: int
    signed_prekey_pub: str
    signed_prekey_signature: str


class ReplenishOneTimePrekeysRequest(BaseModel):
    one_time_prekeys: list[OneTimePrekey] = Field(default_factory=list)
