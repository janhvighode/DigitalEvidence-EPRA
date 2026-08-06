from pydantic import BaseModel
from datetime import datetime


class TimelineResponse(BaseModel):

    id: int

    event: str

    performed_by: int

    performed_by_role: str

    created_at: datetime

    class Config:
        from_attributes = True