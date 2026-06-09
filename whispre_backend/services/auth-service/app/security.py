import hashlib
import base64
from datetime import datetime

from passlib.context import CryptContext
from whispre_common.auth import build_token, decode_token as decode_jwt_token, hash_token

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
    return build_token(
        sub,
        token_type,
        ttl_seconds,
        secret=settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )


def create_access_token(user_id: str) -> str:
    token, _, _ = _build_token(user_id, 'access', settings.access_token_ttl_seconds)
    return token


def create_refresh_token(user_id: str) -> tuple[str, str, datetime]:
    return _build_token(user_id, 'refresh', settings.refresh_token_ttl_seconds)


def decode_token(token: str, expected_type: str | None = None) -> dict:
    return decode_jwt_token(
        token,
        secret=settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
        expected_type=expected_type,
    )
