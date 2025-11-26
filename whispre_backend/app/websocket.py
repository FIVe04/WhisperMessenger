# app/routes/websocket.py
from datetime import datetime

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends
from fastapi.exceptions import HTTPException
from typing import Dict, List
from app.auth import decode_access_token
from app.database import get_db
from sqlalchemy.orm import Session
from app.models import User, Message, MessageStatus
from uuid import UUID
from starlette.websockets import WebSocketState

router = APIRouter()


active_connections: Dict[UUID, List[WebSocket]] = {}


async def get_current_user(websocket: WebSocket, db: Session):
    token = websocket.query_params.get("token")
    print('token', token)
    if not token:
        await websocket.close(code=1008)
        return None
    try:
        token_data = decode_access_token(token)
        user_id = token_data.user_id
    except Exception:
        await websocket.close(code=1008)
        return None
    user = db.query(User).filter(User.id == user_id).first()
    print('user', user)
    if not user:
        await websocket.close(code=1008)
        return None

    return user


@router.websocket("/ws/messages")
async def websocket_endpoint(websocket: WebSocket, db: Session = Depends(get_db)):
    await websocket.accept()
    try:
        user = await get_current_user(websocket, db)
        if not user:
            return
        if user.id not in active_connections:
            active_connections[user.id] = []
        active_connections[user.id].append(websocket)

        while True:
            data = await websocket.receive_json()
            action = data.get("action")

            if action == "send_message":
                recipient_id = UUID(data["recipient_user_id"])
                message = Message(
                    sender_user_id=user.id,
                    sender_device_id=data["sender_device_id"],
                    recipient_user_id=recipient_id,
                    recipient_device_id=data["recipient_device_id"],
                    ciphertext=data["ciphertext"].encode(),
                    content_type=data["content_type"],
                    status=MessageStatus.pending
                )
                db.add(message)
                db.commit()
                db.refresh(message)
                print(active_connections)
                print(message)
                if recipient_id in active_connections:
                    for conn in active_connections[recipient_id]:
                        if conn.application_state == WebSocketState.CONNECTED:
                            await conn.send_json({
                                "action": "new_message",
                                "message": {
                                    "id": str(message.id),
                                    "sender_user_id": str(message.sender_user_id),
                                    "sender_device_id": message.sender_device_id,
                                    "recipient_user_id": str(message.recipient_user_id),
                                    "recipient_device_id": message.recipient_device_id,
                                    "ciphertext": data["ciphertext"],
                                    "content_type": message.content_type,
                                    "status": message.status.value,
                                    "created_at": str(message.created_at)
                                }
                            })

            elif action == "update_status":
                msg_id = UUID(data["message_id"])
                status = data["status"]
                msg = db.query(Message).filter(Message.id == msg_id).first()
                if msg:
                    msg.status = MessageStatus(status)
                    if status == "delivered":
                        msg.delivered_at = datetime.now()
                    elif status == "read":
                        msg.read_at = datetime.now()
                    db.commit()

                    sender_id = msg.sender_user_id
                    if sender_id in active_connections:
                        for conn in active_connections[sender_id]:
                            await conn.send_json({
                                "action": "status_update",
                                "message_id": str(msg.id),
                                "status": msg.status.value
                            })


    except WebSocketDisconnect:
        if 'user' in locals() and user and user.id in active_connections:
            active_connections[user.id].remove(websocket)
            if not active_connections[user.id]:
                del active_connections[user.id]
