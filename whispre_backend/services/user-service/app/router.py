import logging

from fastapi import APIRouter, Depends, Query
from whispre_common.logging import log_event

from .dependencies import require_auth
from .schemas import UserSummary
from .service import get_user, search_users_by_username

router = APIRouter(prefix='/v1/users')
logger = logging.getLogger('user-service.domain')


@router.get('/search', response_model=list[UserSummary])
def search_users(
    username: str = Query(min_length=1, max_length=64),
    current_user_id: str = Depends(require_auth),
) -> list[UserSummary]:
    results = search_users_by_username(username)
    log_event(
        logger,
        logging.INFO,
        'user_search_completed',
        user_id=current_user_id,
        result_count=len(results),
    )
    return results


@router.get('/me', response_model=UserSummary)
def me(current_user_id: str = Depends(require_auth)) -> UserSummary:
    return get_user(current_user_id)
