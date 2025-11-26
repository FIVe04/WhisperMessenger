from datetime import datetime

from app.models import (
    User, Session, Device, OneTimePreKey, Session
)


def get_user_by_email(db, email: str):
    return db.query(User).filter(User.email == email).first()


def get_user_by_username(db, username: str):
    return db.query(User).filter(User.username == username).first()


def get_user_by_id(db, id):
    return db.query(User).filter(User.id == id).first()


def add_user(db, username:str, email:str, password_hash:str):
    to_add = User(
        username=username,
        email=email,
        password_hash=password_hash,
        created_at=datetime.now()
                  )

    db.add(to_add)
    db.flush()
    db.refresh(to_add)
    return to_add
