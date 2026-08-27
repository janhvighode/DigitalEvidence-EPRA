from pydantic import BaseModel
from typing import Optional
from datetime import datetime


# Used when Administrator creates a new case
class CaseCreate(BaseModel):
    title: str
    description: Optional[str] = None
    investigator_id: int
    priority: str


# Used when displaying case details
class CaseResponse(BaseModel):
    id: int
    case_id: str
    title: str
    description: Optional[str]
    investigator_id: int
    priority: str
    status: str
    created_by: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True