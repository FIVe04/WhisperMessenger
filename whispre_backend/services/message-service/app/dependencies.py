from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from whispre_common.logging import bind_user_id

from .security import decode_access_token

security = HTTPBearer(auto_error=True)


def require_auth(credentials: HTTPAuthorizationCredentials = Depends(security)) -> str:
    payload = decode_access_token(credentials.credentials)
    user_id = str(payload['sub'])
    bind_user_id(user_id)
    return user_id
