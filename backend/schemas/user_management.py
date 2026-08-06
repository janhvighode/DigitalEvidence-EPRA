from pydantic import BaseModel
from typing import Optional


class UserResponse(BaseModel):
    id: int
    full_name: str
    email: str
    role: str
    cyber_cell: str
    phone_number: Optional[str]
    is_active: bool

    class Config:
        from_attributes = True


class UserUpdate(BaseModel):
    full_name: Optional[str] = None
    phone_number: Optional[str] = None
    cyber_cell: Optional[str] = None


# ← THIS WAS MISSING
class UserStatusUpdate(BaseModel):
    is_active: bool


class UserStatusResponse(BaseModel):
    message: str
    user_id: int
    is_active: bool