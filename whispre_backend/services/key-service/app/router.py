from fastapi import APIRouter, Depends, Path, Query

from .dependencies import require_auth
from .schemas import KeyBundle, ReplenishOneTimePrekeysRequest, UpdateDeviceBundleRequest
from .service import (
    claim_user_one_time_prekey,
    get_user_key_bundles,
    replenish_prekeys,
    update_bundle,
)

router = APIRouter(prefix='/v1/keys')


@router.get('/users/{user_id}/bundles', response_model=list[KeyBundle])
def get_user_bundles(
    user_id: str = Path(...),
    _current_user_id: str = Depends(require_auth),
) -> list[KeyBundle]:
    return get_user_key_bundles(user_id)


@router.post('/users/{user_id}/one-time-prekey/claim', response_model=KeyBundle)
def claim_one_time_prekey(
    user_id: str = Path(...),
    device_id: str | None = Query(default=None),
    _current_user_id: str = Depends(require_auth),
) -> KeyBundle:
    return claim_user_one_time_prekey(user_id, device_id)


@router.put('/devices/{device_id}/bundle')
def update_device_bundle(
    payload: UpdateDeviceBundleRequest,
    device_id: str = Path(...),
    current_user_id: str = Depends(require_auth),
) -> dict[str, str]:
    update_bundle(current_user_id, device_id, payload)
    return {'status': 'ok'}


@router.post('/devices/{device_id}/one-time-prekeys/replenish')
def replenish_one_time_prekeys(
    payload: ReplenishOneTimePrekeysRequest,
    device_id: str = Path(...),
    current_user_id: str = Depends(require_auth),
) -> dict[str, int]:
    inserted = replenish_prekeys(current_user_id, device_id, payload)
    return {'uploaded': inserted}
