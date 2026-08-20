from pydantic import BaseModel
from typing import Optional


class ProfileResponse(BaseModel):
    id: int
    full_name: str
    username: str
    email: str
    phone_number: Optional[str]
    role: str
    cyber_cell_id: int
    cyber_cell: str

    class Config:
        from_attributes = True


class ProfileUpdate(BaseModel):
    full_name: Optional[str] = None
    phone_number: Optional[str] = None