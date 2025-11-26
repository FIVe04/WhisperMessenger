from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException

from app.auth import get_current_user
from app.database import get_db
from app.models import Message
from app.schemas import MessageCreate, MessageResponse
from sqlalchemy.orm import Session
from app.websocket import active_connections

router = APIRouter(prefix="/messages", tags=["messages"])


# TODO: добавить оффлайн отправку
@router.post("/send", response_model=MessageResponse)
async def send_message(
    msg: MessageCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    new_msg = Message(
        sender_user_id=current_user.id,
        sender_device_id=msg.sender_device_id,
        recipient_user_id=msg.recipient_user_id,
        recipient_device_id=msg.recipient_device_id,
        ciphertext=msg.ciphertext,
        content_type=msg.content_type,
        status="pending"
    )
    db.add(new_msg)
    db.commit()
    db.refresh(new_msg)

    recipient_id = new_msg.recipient_user_id
    if recipient_id in active_connections:
        for ws in active_connections[recipient_id]:
            try:
                await ws.send_json({
                    "action": "new_message",
                    "message": {
                        "id": str(new_msg.id),
                        "sender_user_id": str(new_msg.sender_user_id),
                        "sender_device_id": new_msg.sender_device_id,
                        "recipient_user_id": str(new_msg.recipient_user_id),
                        "recipient_device_id": new_msg.recipient_device_id,
                        "ciphertext": new_msg.ciphertext.decode() if isinstance(new_msg.ciphertext, bytes) else new_msg.ciphertext,
                        "content_type": new_msg.content_type,
                        "status": new_msg.status.value,
                        "created_at": str(new_msg.created_at),
                    }
                })
                new_msg.status = "delivered"
                new_msg.delivered_at = datetime.now()
                db.commit()
            except Exception as e:
                print(f"❌ WebSocket send failed: {e}")

    return new_msg


@router.get("/inbox", response_model=list[MessageResponse])
def get_inbox_messages(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),

):
    print(current_user.id, current_user.email)
    messages = db.query(Message).filter(
        Message.recipient_user_id == current_user.id
    ).order_by(Message.created_at.desc()).all()
    return messages


@router.get("/history/{user_id}", response_model=list[MessageResponse])
def get_chat_history(
    user_id: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    messages = db.query(Message).filter(
        ((Message.sender_user_id == current_user.id) & (Message.recipient_user_id == user_id)) |
        ((Message.sender_user_id == user_id) & (Message.recipient_user_id == current_user.id))
    ).order_by(Message.created_at.asc()).all()

    return messages

@router.patch("/{message_id}/status")
def update_message_status(
    message_id: UUID,
    status: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    msg = db.query(Message).filter(
        Message.id == message_id,
        Message.recipient_user_id == current_user.id
    ).first()

    if not msg:
        raise HTTPException(status_code=404, detail="Message not found")

    if status == "delivered":
        msg.status = "delivered"
        msg.delivered_at = datetime.now()
    elif status == "read":
        msg.status = "read"
        msg.read_at = datetime.now()
    else:
        raise HTTPException(status_code=400, detail="Invalid status")

    db.commit()
    return {"detail": "Status updated"}