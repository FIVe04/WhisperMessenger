import hashlib
import uuid
import base64
from datetime import UTC, datetime, timedelta

import jwt
from fastapi import HTTPException, status
from passlib.context import CryptContext

from .config import settings

pwd_context = CryptContext(schemes=['bcrypt'], deprecated='auto')


def _normalize_password_for_bcrypt(password: str) -> str:
    # bcrypt accepts only first 72 bytes; pre-hash to keep full password entropy.
    digest = hashlib.sha256(password.encode('utf-8')).digest()
    return base64.b64encode(digest).decode('ascii')


def hash_password(password: str) -> str:
    return pwd_context.hash(_normalize_password_for_bcrypt(password))


def verify_password(password: str, password_hash: str) -> bool:
    return pwd_context.verify(_normalize_password_for_bcrypt(password), password_hash)


def _build_token(sub: str, token_type: str, ttl_seconds: int) -> tuple[str, str, datetime]:
    now = datetime.now(UTC)
    exp = now + timedelta(seconds=ttl_seconds)
    jti = str(uuid.uuid4())
    payload = {
        'sub': sub,
        'typ': token_type,
        'jti': jti,
        'iat': int(now.timestamp()),
        'exp': int(exp.timestamp()),
    }
    token = jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)
    return token, jti, exp


def create_access_token(user_id: str) -> str:
    token, _, _ = _build_token(user_id, 'access', settings.access_token_ttl_seconds)
    return token


def create_refresh_token(user_id: str) -> tuple[str, str, datetime]:
    return _build_token(user_id, 'refresh', settings.refresh_token_ttl_seconds)


def decode_token(token: str, expected_type: str | None = None) -> dict:
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except jwt.PyJWTError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid token') from exc

    if expected_type and payload.get('typ') != expected_type:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid token type')

    return payload


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode('utf-8')).hexdigest()
