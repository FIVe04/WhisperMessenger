from fastapi import HTTPException, status
from sqlalchemy import func, select
from whispre_common.models import User

from .db import get_db
from .schemas import UserSummary


def search_users_by_username(username: str) -> list[UserSummary]:
    with get_db() as session:
        users = session.scalars(
            select(User)
            .where(
                User.deleted_at.is_(None),
                func.lower(User.username).contains(username.lower()),
            )
            .order_by(User.username)
            .limit(20)
        ).all()

    return [UserSummary(id=user.id, username=user.username) for user in users]


def get_user(user_id: str) -> UserSummary:
    with get_db() as session:
        user = session.scalar(
            select(User).where(
                User.id == user_id,
                User.deleted_at.is_(None),
            )
        )

    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found')
    return UserSummary(id=user.id, username=user.username)
