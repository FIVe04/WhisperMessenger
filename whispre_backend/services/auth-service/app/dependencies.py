from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from whispre_common.logging import bind_user_id

from .security import decode_token

security = HTTPBearer(auto_error=True)


def get_current_user_id(credentials: HTTPAuthorizationCredentials = Depends(security)) -> str:
    payload = decode_token(credentials.credentials, expected_type='access')
    user_id = str(payload['sub'])
    bind_user_id(user_id)
    return user_id
