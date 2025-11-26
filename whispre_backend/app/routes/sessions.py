from fastapi import APIRouter

router = APIRouter(prefix="/sessions", tags=["sessions"])


@router.get("/")
async def root_sessions():
    return {"route": "sessions"}


