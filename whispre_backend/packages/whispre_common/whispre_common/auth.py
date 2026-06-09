import hashlib
import uuid
from datetime import UTC, datetime, timedelta

import jwt
from fastapi import HTTPException, status


def build_token(
    subject: str,
    token_type: str,
    ttl_seconds: int,
    *,
    secret: str,
    algorithm: str,
) -> tuple[str, str, datetime]:
    now = datetime.now(UTC)
    expires_at = now + timedelta(seconds=ttl_seconds)
    token_id = str(uuid.uuid4())
    payload = {
        'sub': subject,
        'typ': token_type,
        'jti': token_id,
        'iat': int(now.timestamp()),
        'exp': int(expires_at.timestamp()),
    }
    token = jwt.encode(payload, secret, algorithm=algorithm)
    return token, token_id, expires_at


def decode_token(
    token: str,
    *,
    secret: str,
    algorithm: str,
    expected_type: str | None = None,
) -> dict:
    try:
        payload = jwt.decode(token, secret, algorithms=[algorithm])
    except jwt.PyJWTError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid token') from exc

    if expected_type and payload.get('typ') != expected_type:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid token type')

    return payload


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode('utf-8')).hexdigest()
