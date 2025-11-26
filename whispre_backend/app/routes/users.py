from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from uuid import uuid4
from app.database import get_db
from app.models import User, Session as UserSession, Message
from app.schemas import UserCreate, UserResponse, Token, UserLogin, FriendOut, UserByUsernameRequest
from app.auth import get_password_hash, verify_password, create_access_token, create_refresh_token, get_current_user
from sqlalchemy import or_, distinct, and_
from fastapi.security import OAuth2PasswordRequestForm

router = APIRouter(prefix="/users", tags=["Users"])


@router.post("/register")
def register_user(user_data: UserCreate, db: Session = Depends(get_db)):
    existing_user = db.query(User).filter(
        (User.email == user_data.email) | (User.username == user_data.username)
    ).first()
    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="User with this email or username already exists",
        )
    print(user_data.password)
    hashed_password = get_password_hash(user_data.password)
    new_user = User(
        username=user_data.username,
        email=user_data.email,
        password_hash=hashed_password,
    )
    # TODO: refactor: separate into crud
    db.add(new_user)
    db.commit()
    db.refresh(new_user)

    return {"id": new_user.id}


@router.post("/login", response_model=Token)
def login_user(user_data: UserLogin, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == user_data.email).first()
    if not user or not verify_password(user_data.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    access_token = create_access_token({"user_id": str(user.id)})
    refresh_token = create_refresh_token({"user_id": str(user.id)})

    new_session = UserSession(
        id=uuid4(),
        user_id=user.id,
        refresh_token_hash=get_password_hash(refresh_token),
    )
    db.add(new_session)
    db.commit()

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
    }


@router.get("/me", response_model=UserResponse)
def read_current_user(current_user: User = Depends(get_current_user)):
    return current_user


@router.get("/friends", response_model=List[FriendOut])
def read_friends(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    to_me = db.query(Message.recipient_user_id).filter(Message.sender_user_id == current_user.id).all()
    from_me = db.query(Message.sender_user_id).filter(Message.recipient_user_id == current_user.id).all()

    to_me_ids = [x[0] for x in to_me]
    from_me_ids = [x[0] for x in from_me]

    friend_ids = [fid for fid in set(to_me_ids + from_me_ids) if fid != current_user.id]
    if not friend_ids:
        return []

    friends = db.query(User).filter(User.id.in_(friend_ids)).all()

    return friends


@router.get('/all', response_model=List[FriendOut])
def get_all_users(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    res = db.query(User).all()
    return res


@router.get('/by_username', response_model=FriendOut)
def get_user_by_username(username: str, db: Session = Depends(get_db)):
    res = db.query(User).filter(User.username == username).first()
    if not res:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    return res

@router.get('/by_id', response_model=FriendOut)
def get_user_by_username(uid: str, db: Session = Depends(get_db)):
    res = db.query(User).filter(User.id == uid).first()
    if not res:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    return res