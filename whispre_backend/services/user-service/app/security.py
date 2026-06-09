from whispre_common.auth import decode_token

from .config import settings


def decode_access_token(token: str) -> dict:
    return decode_token(
        token,
        secret=settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
        expected_type='access',
    )
