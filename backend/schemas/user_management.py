from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class UserResponse(BaseModel):
    id: int
    full_name: str
    username: str
    email: str
    phone_number: Optional[str] = None
    role_id: int
    cyber_cell_id: int
    is_first_login: bool
    is_active: bool
    created_at: datetime

    
    class Config:
        from_attributes = True


class UserUpdate(BaseModel):
    full_name: Optional[str] = None
    phone_number: Optional[str] = None
    cyber_cell_id: Optional[int] = None


# ← THIS WAS MISSING
class UserStatusUpdate(BaseModel):
    is_active: bool


class UserStatusResponse(BaseModel):
    message: str
    user_id: int
    is_active: bool