from fastapi import APIRouter, Depends, Header

from .dependencies import get_current_user_id
from .schemas import (
    AuthTokens,
    DeviceRegisterRequest,
    DeviceRegisterResponse,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    RegisterRequest,
)
from .service import (
    login_user,
    logout_session,
    refresh_session,
    register_device_for_user,
    register_user,
)

router = APIRouter()


@router.post('/v1/auth/register', response_model=AuthTokens)
def register(payload: RegisterRequest) -> AuthTokens:
    return register_user(payload)


@router.post('/v1/auth/login', response_model=AuthTokens)
def login(payload: LoginRequest) -> AuthTokens:
    return login_user(payload)


@router.post('/v1/auth/refresh', response_model=AuthTokens)
def refresh(payload: RefreshRequest) -> AuthTokens:
    return refresh_session(payload.refresh_token)


@router.post('/v1/auth/logout')
def logout(payload: LogoutRequest) -> dict[str, str]:
    logout_session(payload.refresh_token)
    return {'status': 'ok'}


@router.post('/v1/auth/devices/register', response_model=DeviceRegisterResponse)
def register_device(
    payload: DeviceRegisterRequest,
    user_id: str = Depends(get_current_user_id),
    x_device_id: str | None = Header(default=None, alias='X-Device-Id'),
) -> DeviceRegisterResponse:
    return register_device_for_user(payload, user_id, x_device_id)
