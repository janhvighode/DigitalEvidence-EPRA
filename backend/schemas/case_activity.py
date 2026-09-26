from pydantic import BaseModel
from datetime import datetime


class KanbanCase(BaseModel):
    id: int
    case_id: str
    title: str
    investigator_id: int | None
    priority: str
    status: str
    created_at: datetime

    class Config:
        from_attributes = True


class AssignInvestigatorRequest(BaseModel):
    investigator_id: int


class AssignInvestigatorResponse(BaseModel):
    message: str
    case_id: str
    investigator_name: str

class AssignCyberExpertRequest(BaseModel):
    cyber_expert_id: int


class AssignCyberExpertResponse(BaseModel):
    message: str
    case_id: str
    cyber_expert_name: str

