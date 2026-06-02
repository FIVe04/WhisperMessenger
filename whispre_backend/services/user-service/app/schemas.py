from pydantic import BaseModel


class UserSummary(BaseModel):
    id: str
    username: str
